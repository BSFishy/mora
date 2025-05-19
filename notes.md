# notes

writing this because im currently stuck on what to do next. just gonna write out
how i think it should work all the way through so that i know what to do next.

1. identify directory to start searching for modules
1. lex and parse files -> ast
1. non-semantic ast -> resolved modules
1. resolved modules -> k8s manifests

## module manager

i think it makes sense to make this the root entry into the system. i think i
want to point it to a directory (like, point it to sample). it should iterate
the directory then pass the directory to the lexer and parser phase. i think it
needs to maintain a list of all the modules so they can cross reference each
other. might need multiple phases of resolution to properly support the
style of resolution that i need, but idk i dont think cyclical references dont
make sense maybe.

## parsing + lexing

uhm so yeah this is pretty self explanatory. i want to parse into pretty
unresolved structures i think. lex is simple, i _think_ i want to parse into
very very abstract structures. the root file is a block, blocks can have
assignments and nested blocks. then we actually resolve the blocks and
statements in sema or something like that.

## sema

so this is where we actually like resolve the separate blocks. a "module"
container is created with like arrays and things for like services and whatnot.
this is also where we figure out the right assignments and all that. but it
should be pretty simple cuz its like the entire language is like assignments and
blocks. should be pretty easy i think

## codegen

gonna call this codegen so i can say i made a proper compiler :3 but it is kinda
codegen cuz ill actually be generating k8s manifests. i wanna be able to debug
the output of the compiler so i will directly generate k8s manifests but ill
also be sure to have it able to deploy those manifests as well. i want this
stuff to be configurable so it should give me a prompt to input info and all
that whatever.
