# Vim PostgreSQL syntax plugin

![pgsql syntax highlighting](https://raw.github.com/lifepillar/Resources/master/pgsql/pgsql.png)

This plugin provides syntax highlighting and auto-completion support for
PostgreSQL version 9.6 or above and for some of its extensions, including:

- PL/pgSQL;
- [PostGIS](http://postgis.net) (including PostGIS Topology);
- [pgRouting](http://pgrouting.org);
- [pgTap](http://pgtap.org).

Besides, syntax highlighting for any language may be activated inside functions
(see below).


# Installation

If your Vim supports packages (`echo has('packages')` prints `1`), I strongly
recommend that you use them. Just clone this repo inside `pack/*/start`, e.g.,

    cd ~/.vim
    git clone https://github.com/lifepillar/pgsql.vim.git pack/bundle/start/pgsql

Otherwise, if you don't have a preferred installation method, I recommend
installing [Pathogen](https://github.com/tpope/vim-pathogen), and then simply
copy and paste:

    cd ~/.vim/bundle
    git clone https://github.com/lifepillar/pgsql.vim.git


# Usage

**For thorough documentation, see `:h pgsql.txt`.**

Files with a `.pgsql` suffix are highlighted out of the box. If you want to
highlight `.sql` files using this plugin by default, add this to your `.vimrc`
(see `:h ft_sql.txt`):

    let g:sql_type_default = 'pgsql'

Alternatively, after loading a `.sql` file use this command:

    :SQLSetType pgsql.vim

To set the file type in new buffers use:

    :let b:sql_type_override='pgsql' | set ft=sql

Code between `$pgsql$` or `$$` pairs is treated as PL/pgSQL and highlighted
accordingly:

![PL/pgSQL snippet](https://raw.github.com/lifepillar/Resources/master/pgsql/plpgsql.png)

You may set `g:pgsql_pl` to a list of file types to be used in user-defined
functions. For example, after setting:

    let g:pgsql_pl = ['python']

code between `$python$` pairs will be highlighted as Python:

![PL/Pythonu snippet](https://raw.github.com/lifepillar/Resources/master/pgsql/plpython.png)


# Snippets

UltiSnips snippets have been removed in commit
[aae77099](https://github.com/lifepillar/pgsql.vim/commit/aae77099bccaa5f443994821130688e0c30182d9)
essentially for three reasons:

- not everyone using this plugin uses UltiSnips;
- UltiSnips already provides some basic SQL snippets;
- snippets's style and behaviour are a matter of personal taste.

So, if you want PostgreSQL-specific snippets, you'd better write your own.


# Acknowledgments

This plugin was originally based on code from
[space::tekk](https://github.com/spacetekk/pgsql.vim) (and completely
rewritten).

