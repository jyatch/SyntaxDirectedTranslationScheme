CC = gcc 
CFLAGS = -g #-fsanitize=address,undefined

OBJs = parse.tab.o symtab.o attr.o instrutil.o lex.yy.o 

default: codegen 

# Jake: I had to remove the flag "-fl"
codegen: ${OBJs}
	${CC} ${CFLAGS} ${OBJs} -o codegen -lfl

lex.yy.c: scan.l parse.tab.h attr.h
	flex -i scan.l

parse.tab.c: parse.y attr.h symtab.h instrutil.h
	bison -dv parse.y

parse.tab.h: parse.tab.c

clean:
	rm -f codegen lex.yy.c *.o parse.tab.[ch] parse.output iloc.out

depend:
	makedepend -I. *.c
# DO NOT DELETE THIS LINE -- make depend depends on it.
