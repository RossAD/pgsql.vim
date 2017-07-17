-- To generate the syntax file, proceed as follows:
--
-- 1. createdb -T template0 vim_pgsql_syntax
-- 2. psql -f pgsql.sql vim_pgsql_syntax
--
-- ...or simply use the provided Makefile.

\set QUIET 1
\pset border 0
\pset columns 0
\pset expanded off
\pset fieldsep ' '
\pset footer off
\pset format unaligned
\pset null ''
\pset numericlocale off
\pset pager off
\pset recordsep '\n'
\pset title
\pset tuples_only on
\o

start transaction;

set local client_min_messages to 'warning';
set local schema 'public';

select 'Populating the schema...';

drop table if exists errcodes;

create table errcodes (
  "errcode" text primary key
);

\copy errcodes from program 'cat errcodes.txt | awk -F "[ ]+" ''{ if ($1 != "#" && $4 != "-" && $4 != "") { print $4 } }'' | sort | uniq'


create or replace function extension_names()
returns table (
          extname    name,
          extversion text
        )
language sql stable
set search_path to "pg_catalog" as
$$
  select name, default_version from pg_available_extensions()
   where name not in ( -- Extensions to skip
    'citus',
    'hstore_plpython3u',
    'ltree_plpython3u',
    'plr' -- Not available for PostgreSQL 9.6?
  );
$$;


create or replace function recommended_extensions()
returns table (extname text)
language sql immutable as
$$
  values ('pgrouting'), ('pgtap'), ('pldbgapi'), ('postgis'), ('postgis_topology');
$$;


create or replace function create_extensions()
returns setof void
language plpgsql volatile
set search_path to "public", "pg_catalog"
set client_min_messages to 'error' as
$$
declare
  _fn name;
begin
  for _fn in select extname from extension_names() loop
    execute 'create extension if not exists "' || _fn || '" cascade';
  end loop;
  return;
end;
$$;

-- TODO:
-- auth_delay
-- auto_explain
-- dummy_seclabel
-- passwordcheck
-- sepgsql
-- spi
-- test_decoding
-- test_parser
-- test_shm_mq


-- Among the keywords, we distinguish those corresponding to 'statements', as
-- other SQL syntax types do.
create or replace function get_statements()
returns table (stm text)
language sql immutable as
$$
  values ('create'), ('select'), ('abort'), ('alter'), ('analyze'), ('begin'),
         ('checkpoint'), ('close'), ('cluster'), ('comment'), ('commit'), ('constraints'),
         ('copy'), ('deallocate'), ('declare'), ('delete'), ('discard'),
         ('do'), ('drop'), ('end'), ('execute'), ('explain'), ('fetch'), ('grant'),
         ('import'), ('insert'), ('label'), ('listen'), ('load'), ('lock'), ('move'),
         ('notify'), ('prepare'), ('prepared'), ('reassign'), ('reindex'), ('refresh'), ('release'),
         ('replace'), ('reset'), ('revoke'), ('rollback'), ('savepoint'), ('security'),
         ('select'), ('set'), ('show'), ('start'), ('transaction'), ('truncate'),
         ('unlisten'), ('update'), ('vacuum'), ('values'), ('work');
$$;


-- Built-in keywords (except statements)
create or replace function get_keywords()
returns table (keyword text)
language sql stable
set search_path to "public", "pg_catalog" as
$$
  select word from pg_get_keywords()
  except
  select stm from get_statements();
$$;


-- Keywords that cannot be extracted from system catalogs
create or replace function get_additional_keywords()
returns table (keyword text)
language sql immutable as
$$
  -- Serial types are not true types, but merely a notational convenience for creating unique identifier columns.
  -- See https://www.postgresql.org/docs/current/static/datatype-numeric.html#DATATYPE-SERIAL
  values ('smallserial'), ('serial'), ('bigserial'), ('serial2'), ('serial4'), ('serial8');
$$;


create or replace function get_builtin_functions()
returns table (synfunction text)
language sql stable
set search_path to "information_schema" as
$$
  select distinct routine_name::text
    from routines
   where specific_schema = 'pg_catalog';
$$;


create or replace function get_types()
returns table ("type" text)
language sql stable
set search_path to "pg_catalog" as
$$
  select distinct typname::text
    from pg_type
   where typname not like '\_%'
     and typname not like 'pg_toast_%';
$$;


-- Get the list of functions, tables, types and views installed by a given extension.
-- Query adapted from psql (\set ECHO_HIDDEN ON and \dx+ <extname> to see the query).
create or replace function get_extension_objects(_extname name)
returns table (
          synclass text,
          synkeyword text
        )
language sql stable
set search_path to "pg_catalog" as
$$
  select  distinct
          regexp_replace(pg_catalog.pg_describe_object(classid, objid, 0), '^(function|table|type|view).*', '\1') as synclass,
          regexp_replace(pg_catalog.pg_describe_object(classid, objid, 0), '^(function|table|type|view)\s+([^\(]+).*', '\2') as synkeyword
    from  pg_depend
   where  refclassid = 'pg_catalog.pg_extension'::pg_catalog.regclass
     and  refobjid = (select e.oid from pg_extension e where e.extname ~ ('^(' || _extname || ')$'))
     and  deptype = 'e'
     and  pg_describe_object(classid, objid, 0) ~* '^(function|table|type|view)\s+[^_]'
     and not pg_describe_object(classid, objid, 0) ~* '\w+\.\_'; -- Do not match things like 'public._some_func()';
$$;


-- Constants that cannot be extracted from system catalogs
create or replace function get_additional_constants()
returns table (keyword text)
language sql immutable as
$$
  values ('pg_catalog'), ('information_schema');
$$;


create or replace function get_catalog_tables()
returns table (table_name text)
language sql stable
set search_path to "information_schema" as
$$
  select table_name::text
    from tables
   where table_catalog = 'vim_pgsql_syntax' -- database name
     and table_name not like '\_%'
     and table_schema in ('pg_catalog', 'information_schema');
$$;


create or replace function get_errcodes()
returns table (errcode text)
language sql stable
set search_path to "public" as
$$
  select "errcode" from errcodes;
$$;


-- Format keywords to use in a Vim syntax file.
-- _keywords is a list of keywords.
-- _kind is the highlight group (without the 'sql' prefix).
-- _wrap specifies the number of keywords per line.
--
-- Example: select vim_format('[create, select]', 'Statement', 6).
create or replace function vim_format(
  _keywords text[],
  _kind text,
  _wrap integer default 8)
returns setof text
language plpgsql stable
set search_path to "public" as
$$
begin
  return query
    with T as (
      select rank() over (order by keyword) as num, keyword
        from unnest(_keywords) K(keyword)
    )
    select 'syn keyword sql' || _kind || ' contained ' || string_agg(keyword, ' ')
      from T
     group by (num - 1) / _wrap
     order by (num - 1) / _wrap;
  return;
end;
$$;


-- Define keywords for all extensions
create or replace function vim_format_extensions()
returns setof text
language plpgsql stable
set search_path to "public" as
$$
declare
  _ext record;
begin
  for _ext in select extname, extversion from extension_names() loop

    return query
    select '" Extension: ' || _ext.extname || ' (v' || _ext.extversion || ')';

    return query
    select 'if index(get(g:, ''pgsql_disabled_extensions'', []), ''' || _ext.extname || ''') == -1';

    return query
    with T as (
      select rank() over (partition by synclass order by synkeyword) num, synclass, synkeyword
        from get_extension_objects(_ext.extname)
      )
      select '  syn keyword sql' || initcap(synclass) || ' contained ' || string_agg(regexp_replace(synkeyword, '^\w+\.|"', '', 'g'), ' ') -- remove schema name and double quotes
        from T
      group by synclass, (num - 1) / 6
      order by synclass, (num - 1) / 6;

    return query
      select 'endif " ' || _ext.extname;

  end loop;

  return;
end;
$$;


create or replace function preflight_requirements()
returns setof void
language plpgsql stable
set search_path to "public" as
$$
declare
  _missing text;
begin
  -- Refute to execute if db does not have the right name
  if current_database() <> 'vim_pgsql_syntax' then
    raise exception 'ERROR: Wrong database name!';
  end if;

  -- Print a warning if a recommended extension is missing
  for _missing in
    select extname from recommended_extensions()
    except
    select extname::text from extension_names()
  loop
    raise warning '% is missing. No syntax items will be generated for it.', _missing;
  end loop;
  return;
end;
$$;

-------------------------------------------------------------------------------

select preflight_requirements();

-- Install all the available extensions
select 'Creating extensions...';
select create_extensions();

select 'Generating syntax file...';
\o pgsql.vim

select
$HERE$" Vim syntax file
" Language:     SQL (PostgreSQL dialect), PL/pgSQL, PL/…, PostGIS, …
" Maintainer:   Lifepillar
" Version:      2.0.0
" License:      This file is placed in the public domain.
$HERE$;

select '" Based on ' || substring(version() from '\w+ \d+\.\d+\.\d+');
select '" Automatically generated on ' || current_date || ' at ' || localtime(0);

select
$HERE$
if exists("b:current_syntax")
  finish
endif

syn case ignore
syn sync minlines=100
syn iskeyword @,48-57,192-255,_

syn match sqlIsKeyword  /\<\h\w*\>/   contains=sqlStatement,sqlKeyword,sqlCatalog,sqlConstant,sqlOperator,sqlSpecial,sqlOption,sqlErrorCode,sqlType
syn match sqlIsFunction /\<\h\w*\ze(/ contains=sqlFunction
syn region sqlIsPsql    start=/^\s*\\/ end=/\n/ oneline contains=sqlPsqlCommand,sqlPsqlKeyword,sqlNumber,sqlString

syn keyword sqlSpecial contained false null true
$HERE$;

select '" Statements';
select vim_format(array(select get_statements()), 'Statement');
select '" Types';
select vim_format(array(select get_types()), 'Type');
select 'syn match sqlType /pg_toast_\d\+/';
select '" Built-in functions';
select vim_format(array(select get_builtin_functions()), 'Function', 6);
select vim_format_extensions();
select '" Extensions names';
select vim_format(array(select extname from extension_names() where not extname ~* '-'), 'Constant');
select '" Catalog tables';
select vim_format(array(select get_catalog_tables()), 'Catalog');
select '" Keywords';
select vim_format(array(select get_keywords()), 'Keyword');
select '" Additional keywords and constants';
select vim_format(array(select get_additional_keywords()), 'Keyword');
select vim_format(array(select get_additional_constants()), 'Constant');
select  '" Error codes (Appendix A, Table A-1)';
select vim_format(array(select get_errcodes()), 'ErrorCode', 5);

select
$HERE$
" Numbers
syn match sqlNumber "-\=\<\d*\.\=[0-9_]\>"

" Variables (identifiers starting with an underscore)
syn match sqlVariable "\<_[A-Za-z0-9][A-Za-z0-9_]*\>"

" Strings
syn region sqlIdentifier start=+"+  skip=+\\\\\|\\"+  end=+"+
syn region sqlString     start=+'+  skip=+\\\\\|\\'+  end=+'+ contains=@Spell
syn region sqlString     start=+\$HERE\$+ end=+\$HERE\$+

" Comments
syn region sqlComment    start="/\*" end="\*/" contains=sqlTodo,@Spell
syn match  sqlComment    "#.*$"                contains=sqlTodo,@Spell
syn match  sqlComment    "--.*$"               contains=sqlTodo,@Spell

" Options
syn keyword sqlOption contained client_min_messages search_path

syntax case match

" Psql Keywords
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\[aCfHhortTxz]\>\|\\[?!]/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\c\%(\%(d\|onnect\|onninfo\|opy\%(right\)\?\|rosstabview\)\?\)\>/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\d\>\|\\dS\>+\?\|\\d[ao]S\?\>\|\\d[cDgiLmnOstTuvE]\%(\>\|S\>+\?\)/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\d[AbClx]\>+\?\|\\d[py]\>\|\\dd[pS]\>\?\|\\de[tsuw]\>+\?\|\\df[antw]\?S\?\>+\?\|\\dF[dpt]\?\>+\?\|\\drds\>/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\e\%(cho\|[fv]\|ncoding\|rrverbose\)\?\>/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\g\%(exec\|set\)\?\>/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\ir\?\>/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\l\>+\?\|\\lo_\%(export\|import\|list\|unlink\)\>/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\p\%(assword\|rompt\|set\)\?\>/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\q\%(echo\)\?\>/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\s\>\|\\s[fv]\>+\?\|\\set\%(env\)\?\>/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\t\%(iming\)\?\>/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\unset\>/
syn match sqlPsqlCommand contained nextgroup=sqlPsqlKeyword,sqlNumber,sqlString /\\w\%(atch\)\?\>/
syn keyword sqlPsqlKeyword contained format border columns expanded fieldsep fieldsep_zero footer null
syn keyword sqlPsqlKeyword contained numericlocale recordsep recordsep_zero tuples_only title tableattr pages
syn keyword sqlPsqlKeyword contained unicode_border_linestyle unicode_column_linestyle unicode_header_linestyle
syn keyword sqlPsqlKeyword contained on off auto unaligned pager
syn keyword sqlPsqlKeyword contained AUTOCOMMIT HISTCONTROL PROMPT VERBOSITY SHOW_CONTEXT VERSION
syn keyword sqlPsqlKeyword contained DBNAME USER HOST PORT ENCODING HISTSIZE QUIET

" Todo
syn keyword sqlTodo contained TODO FIXME XXX DEBUG NOTE

syntax case ignore

" PL/pgSQL
syn keyword sqlPlpgsqlKeyword contained alias all array as begin by case close collate column constant
syn keyword sqlPlpgsqlKeyword contained constraint continue current current cursor datatype declare
syn keyword sqlPlpgsqlKeyword contained detail diagnostics else elsif end errcode exception execute
syn keyword sqlPlpgsqlKeyword contained exit fetch for foreach forward found from get hint if
syn keyword sqlPlpgsqlKeyword contained into last loop message move next no notice open perform prepare
syn keyword sqlPlpgsqlKeyword contained query raise relative return reverse rowtype schema
syn keyword sqlPlpgsqlKeyword contained scroll slice sqlstate stacked strict table tg_argv tg_event
syn keyword sqlPlpgsqlKeyword contained tg_level tg_name tg_nargs tg_op tg_relid tg_relname
syn keyword sqlPlpgsqlKeyword contained tg_table_name tg_table_schema tg_tag tg_when then type using
syn keyword sqlPlpgsqlKeyword contained while

syn region plpgsql matchgroup=sqlString start=+\$pgsql\$+ end=+\$pgsql\$+ keepend contains=ALL
syn region plpgsql matchgroup=sqlString start=+\$\$+ end=+\$\$+ keepend contains=ALL

" PL/<any other language>
fun! s:add_syntax(s)
  execute 'syn include @PL' . a:s . ' syntax/' . a:s . '.vim'
  unlet b:current_syntax
  execute 'syn region pgsqlpl' . a:s . ' start=+\$' . a:s . '\$+ end=+\$' . a:s . '\$+ keepend contains=@PL' . a:s
endf

for pl in get(b:, 'pgsql_pl', get(g:, 'pgsql_pl', []))
  call s:add_syntax(pl)
endfor

" Default highlighting
hi def link sqlCatalog        Constant
hi def link sqlComment        Comment
hi def link sqlConstant       Constant
hi def link sqlErrorCode      Special
hi def link sqlFunction       Function
hi def link sqlIdentifier     Identifier
hi def link sqlKeyword        sqlSpecial
hi def link sqlplpgsqlKeyword sqlSpecial
hi def link sqlNumber         Number
hi def link sqlOperator       sqlStatement
hi def link sqlOption         Define
hi def link sqlSpecial        Special
hi def link sqlStatement      Statement
hi def link sqlString         String
hi def link sqlTable          Identifier
hi def link sqlType           Type
hi def link sqlView           sqlTable
hi def link sqlTodo           Todo
hi def link sqlVariable       Identifier
hi def link sqlPsqlCommand    SpecialKey
hi def link sqlPsqlKeyword    Keyword

let b:current_syntax = "sql"
$HERE$;

\o
select 'done!';
commit;
\o


-- Generate test file

create or replace function vim_extensions()
returns setof text
language plpgsql stable
set search_path to "public" as
$$
declare
  _ext record;
begin
  for _ext in select extname from extension_names() loop

    return query
    select '-- Extension: ' || _ext.extname;

    return query
    select regexp_replace(synkeyword, '^\w+\.|"', '', 'g')       ||
           case when synclass = 'function' then '()' else '' end ||
           ' -- ' || synclass
      from get_extension_objects(_ext.extname);

  end loop;

  return;
end;
$$;


\o test.sql
select '-- Statements';
select stm from get_statements();
select '-- Types';
select "type" from get_types();
select 'pg_toast_1234';
select '-- Built-in functions';
select synfunction || '()' from get_builtin_functions();
select vim_extensions();
select '-- Extensions names';
select extname from extension_names() where not extname ~* '-';
select '-- Catalog tables';
select table_name from get_catalog_tables();
select '-- Built-in keywords';
select keyword from get_keywords();
select '-- Additional keywords';
select keyword from get_additional_keywords();
select '-- Additional constants';
select keyword from get_additional_constants();
select '-- Error codes';
select errcode from get_errcodes();
