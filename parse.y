%{
#include <stdio.h>
#include "attr.h"
#include "instrutil.h"
int yylex();
void yyerror(char * s);
#include "symtab.h"

FILE *outfile;
char *CommentBuffer;

// global variable for condexp
regInfo condGlobal;
 
%}

%union {tokentype token;        // used for tokens like ID and CONST, plus lvalue        
        regInfo targetReg;      // used for nonterminals like exp
        idListInfo idl;         // NEW: pointer to an array of strings
        typeInfo tval;          // NEW: used for types and array info
        }

%token PROG PERIOD VAR 
%token INT BOOL ARRAY RANGE OF WRITELN THEN IF 
%token BEG END ASG DO FOR
%token EQ NEQ LT LEQ 
%token AND OR XOR NOT TRUE FALSE 
%token ELSE
%token WHILE
%token <token> ID ICONST 

// declarations for the return type for different nonterminals
%type <targetReg> exp condexp
%type <idl> idlist
%type <targetReg> lvalue    // NEW: changed this from token targetReg
%type <tval> stype     // using a token.type for these but we
%type <tval> type      // just need the int field
%type <token> integer_constant boolean_constant constant // we just need to store numbers here

%start program

%nonassoc EQ NEQ LT LEQ 
%left '+' '-' 
%left '*' 
%left AND OR XOR NOT

%nonassoc THEN
%nonassoc ELSE

%%
program : {emitComment("Assign STATIC_AREA_ADDRESS to register \"r0\"");
           emit(NOLABEL, LOADI, STATIC_AREA_ADDRESS, 0, EMPTY); } 
           PROG ID ';' block PERIOD { }
	;

block	: variables cmpdstmt { }
	;

variables: /* empty */
	| VAR vardcls { }
	;

vardcls	: vardcls vardcl ';' { }
	| vardcl ';' { }
	| error ';' { yyerror("***Error: illegal variable declaration\n");}  
	;
        
vardcl	: idlist ':' type { 
                // store array
                char **ids = $1.idList;
                
                if($3.num == TYPE_ARRAY) {
                        // loop over our IDS and store them in symtab
                        for(int i = 0; ids[i] != NULL; i++) {
                                insert_array(ids[i], $3.num, $3.lowBound, $3.highBound);
                                free(ids[i]);
                        }
                } else {
                        // loop over our IDS and store them in symtab
                        for(int i = 0; ids[i] != NULL; i++) {
                                insert(ids[i], $3.num);
                                free(ids[i]);
                        }
                }
                free(ids);
        } 
	;

idlist	: idlist ',' ID { 
                // loop through the array
                int count = 0;
                while($1.idList[count] != NULL) {
                        count++;
                }

                // allocate a new array
                $$.idList = (char **) malloc(sizeof(char *) * (count + 2));

                // copy everything over
                for(int i = 0; i < count; i++) {
                        $$.idList[i] = $1.idList[i];
                }

                // add on the new ID and null terminate
                $$.idList[count] = strdup($3.str);
                $$.idList[count + 1] = NULL; 
        }
	| ID		{ 
                $$.idList = (char **) malloc(sizeof(char *) * 2);       // creates array
                $$.idList[0] = strdup($1.str);                          // strdup the str field of ID
                $$.idList[1] = NULL;                                    // NULL terminate the array
        }
	;

type    : ARRAY '[' ICONST RANGE ICONST ']' OF stype { 
                $$.num = TYPE_ARRAY;
                $$.arrayType = $8.num;
                $$.lowBound = $3.num;
                $$.highBound = $5.num;
        }
        | stype { $$ = $1; }

stype   : INT { $$.num = TYPE_INT; }
        | BOOL { $$.num = TYPE_BOOL; }

stmtlist : stmtlist ';' stmt { }
	| stmt { }
        | error { yyerror("***Error: illegal statement \n");}
	;

stmt    : ifstmt { }
	| wstmt { }
	| fstmt { }
	| astmt { }
	| writestmt { }
	| cmpdstmt { }
	;

cmpdstmt: BEG stmtlist END { }
	;

ifstmt :  ifhead THEN stmt { int endLabel = pop_label();
                             emit(NOLABEL, CBR, 0, endLabel, endLabel);       // guarenteed jump to endLabel
                             emit(endLabel, EMPTY, EMPTY, EMPTY, EMPTY);
                           }   
        | ifhead THEN stmt ELSE { int label2 = pop_label();
                                  int endLabel = NextLabel();
                                  push_label(endLabel);
                                  emit(NOLABEL, CBR, 0, endLabel, endLabel);
                                  emit(label2, EMPTY, EMPTY, EMPTY, EMPTY);
                                }
          stmt                  { int endLabel = pop_label();
                                  emit(NOLABEL, CBR, 0, endLabel, endLabel); 
                                  emit(endLabel, EMPTY, EMPTY, EMPTY, EMPTY);
                                }
	;

ifhead : IF condexp { int label1 = NextLabel();
                      int label2 = NextLabel();
                      emit(NOLABEL, CBR, $2.targetRegister, label1, label2);
                      emit(label1, EMPTY, EMPTY, EMPTY, EMPTY);
                      push_label(label2);
                    }
        ;

writestmt: WRITELN '(' exp ')' {
                int newReg = NextRegister();
                emit(NOLABEL, LOADI, 1020, newReg, EMPTY);              // loadI 1020 into a newReg 
                emit(NOLABEL, STORE, $3.targetRegister, newReg, EMPTY); // store value of exp into newReg
                emit(NOLABEL, OUTPUT, 1020, EMPTY, EMPTY);              // generate output at @1020
        }
	;

wstmt	: WHILE { 
                // conditional label
                int condLabel = NextLabel();
                push_label(condLabel);
                emit(condLabel, EMPTY, EMPTY, EMPTY, EMPTY);
        }
        condexp { 
                // jump to appropriate branch
                int condLabel = pop_label();
                int bodyLabel = NextLabel();
                int endLabel = NextLabel();
                push_label(condLabel);
                push_label(endLabel);
                
                int condReg = condGlobal.targetRegister;
                // int condReg = $1.targetRegister;

                emit(NOLABEL, CBR, condReg, bodyLabel, endLabel);
                emit(bodyLabel, EMPTY, EMPTY, EMPTY, EMPTY);
          }
          DO stmt  { 
                // recheck the conditional statement
                int endLabel = pop_label();
                int condLabel = pop_label();

                emit(NOLABEL, CBR, 0, condLabel, condLabel);
                emit(endLabel, EMPTY, EMPTY, EMPTY, EMPTY);
          }
	;


fstmt : FOR ID ASG ICONST ',' ICONST DO { 
                int offset = getOffset($2.str);

                if(offset == -1) {
                        sprintf(CommentBuffer, "ERROR: loop variable %s not declared", $2.str);
                        yyerror(CommentBuffer);
                }

                int startVal = $4.num;
                int endVal = $6.num;
                int regStart = NextRegister();

                // (initialization)
                // giving the loop variable its correct starting value
                sprintf(CommentBuffer, "For loop initialization");
                emitComment(CommentBuffer);
                emit(NOLABEL, LOADI, startVal, regStart, EMPTY);        // load start value into a register
                emit(NOLABEL, STOREAI, regStart, 0, offset);            // store value of register into variable

                // (labels)
                int condLabel = NextLabel();
                int bodyLabel = NextLabel();
                int endLabel = NextLabel();
                push_label(endLabel);
                push_label(condLabel);

                // (comparision)
                sprintf(CommentBuffer, "For loop conditional");
                emitComment(CommentBuffer);
                int regVar = NextRegister();
                int regEnd = NextRegister();
                int regCmp = NextRegister();
                emit(condLabel, EMPTY, EMPTY, EMPTY, EMPTY);            // conditional label
                emit(NOLABEL, LOADAI, 0, offset, regVar);               // load loop variable
                emit(NOLABEL, LOADI, endVal, regEnd, EMPTY);            // load end value
                emit(NOLABEL, CMPLE, regVar, regEnd, regCmp);           // compare var and end value
                emit(NOLABEL, CBR, regCmp, bodyLabel, endLabel);        // jump to either body or end
                emit(bodyLabel, EMPTY, EMPTY, EMPTY, EMPTY);            // insert the body label under cond        
                
        }
        stmt { 
                // (increment for loop)
                sprintf(CommentBuffer, "For loop increment");
                emitComment(CommentBuffer);
                
                int offset = getOffset($2.str);

                if(offset == -1) {
                        sprintf(CommentBuffer, "ERROR: loop variable %s not declared", $2.str);
                        yyerror(CommentBuffer);
                }

                int regVar = NextRegister();
                int regOne = NextRegister();
                int regSum = NextRegister();
                int condLabel = pop_label();
                int endLabel = pop_label();

                emit(NOLABEL, LOADI, 1, regOne, EMPTY);
                emit(NOLABEL, LOADAI, 0, offset, regVar);
                emit(NOLABEL, ADD, regOne, regVar, regSum);
                emit(NOLABEL, STOREAI, regSum, 0, offset);

                emit(NOLABEL, CBR, 0, condLabel, condLabel);
                emit(endLabel, EMPTY, EMPTY, EMPTY, EMPTY);
        }
	;

astmt : lvalue ASG exp { 
                sprintf(CommentBuffer, "Store register r%d into location in r%d", $3.targetRegister, $1.targetRegister);
                emitComment(CommentBuffer);
                emit(NOLABEL, STORE, $3.targetRegister, $1.targetRegister, EMPTY);
        }
	;

lvalue	: ID { 
                int offset = getOffset($1.str);

                if(offset == -1) {
                        sprintf(CommentBuffer, "ERROR: variable %s not declared", $1.str);
                        yyerror(CommentBuffer);
                } else {
                        int newReg1 = NextRegister();
                        int newReg2 = NextRegister();
                        $$.targetRegister = newReg2;

                        sprintf(CommentBuffer, "Compute address of variable %s", $1.str);
                        emitComment(CommentBuffer);
                        emit(NOLABEL, LOADI, offset, newReg1, EMPTY);
                        emit(NOLABEL, ADD, 0, newReg1, newReg2);
                }
        }
        |  ID '[' exp ']' { 
                int baseOffset = getOffset($1.str);

                if(baseOffset == - 1) {
                        sprintf(CommentBuffer, "ERROR: array %s not declared", $1.str);
                        yyerror(CommentBuffer);
                } else {
                        int indexReg = $3.targetRegister;
                        int tempReg1 = NextRegister();  // register for MULT
                        int tempReg2 = NextRegister();  // return register
                        int tempReg3 = NextRegister();  // register for 4
                        int tempReg4 = NextRegister();  // register for baseOffset
                        int tempReg5 = NextRegister();  // register for first ADD
                        $$.targetRegister = tempReg2;   // return statement

                        sprintf(CommentBuffer, "Multiply index by 4");
                        emitComment(CommentBuffer);
                        emit(NOLABEL, LOADI, 4, tempReg3, EMPTY);
                        emit(NOLABEL, MULT, indexReg, tempReg3, tempReg1);

                        sprintf(CommentBuffer, "Compute address of array element");
                        emitComment(CommentBuffer);
                        emit(NOLABEL, LOADI, baseOffset, tempReg4, EMPTY);
                        emit(NOLABEL, ADD, 0, tempReg4, tempReg5);
                        emit(NOLABEL, ADD, tempReg5, tempReg1, tempReg2);
                }
        }
        ;

exp	: exp '+' exp		{ int newReg = NextRegister();
                                  $$.targetRegister = newReg;
                                  emit(NOLABEL, 
                                       ADD, 
                                       $1.targetRegister, 
                                       $3.targetRegister, 
                                       newReg);
                                }

        | exp '-' exp		{ int newReg = NextRegister(); 
                                  $$.targetRegister = newReg;
                                  emit(NOLABEL, 
                                       SUB, 
                                       $1.targetRegister, 
                                       $3.targetRegister, 
                                       newReg);
                                }

	| exp '*' exp		{ int newReg = NextRegister(); 
                                  $$.targetRegister = newReg;
                                  emit(NOLABEL, 
                                       MULT, 
                                       $1.targetRegister, 
                                       $3.targetRegister, 
                                       newReg);
                                }
        
        | exp AND exp           { int newReg = NextRegister();
                                  $$.targetRegister = newReg;
                                  emit(NOLABEL, L_AND, $1.targetRegister, $3.targetRegister, newReg);
                                }

        | exp OR exp            { int newReg = NextRegister();
                                  $$.targetRegister = newReg;
                                  emit(NOLABEL, L_OR, $1.targetRegister, $3.targetRegister, newReg);
                                }

        | exp XOR exp           { int newReg = NextRegister();
                                  $$.targetRegister = newReg;
                                  emit(NOLABEL, L_XOR, $1.targetRegister, $3.targetRegister, newReg);
                                }

        | NOT exp               { int tempReg1 = NextRegister();
                                  int tempReg2 = NextRegister();
                                  $$.targetRegister = tempReg2;
                                  emit(NOLABEL, LOADI, 1, tempReg1, EMPTY);
                                  emit(NOLABEL, SUB, tempReg1, $2.targetRegister, tempReg2);
                                }
        
        | ID			{ int newReg = NextRegister();
	                          $$.targetRegister = newReg;
                                  
                                  // getOffset of ID an emit code to load it from memory
                                  int offset = getOffset($1.str);

                                  if(offset == -1) {
                                        sprintf(CommentBuffer, "ERROR: variable %s not declared", $1.str);
                                        yyerror(CommentBuffer);
                                  } else {
                                        sprintf(CommentBuffer, "Load variable %s from offset %d", $1.str, offset);
                                        emitComment(CommentBuffer);
                                        emit(NOLABEL, LOADAI, 0, offset, newReg);
                                  }
                                }
			          

        | ID '[' exp ']'	{ 
                int baseOffset = getOffset($1.str);

                if(baseOffset == -1) {
                        sprintf(CommentBuffer, "ERROR: array %s not declared", $1.str);
                        yyerror(CommentBuffer);
                } else {
                        int indexReg = $3.targetRegister;
                        int tempReg1 = NextRegister();  // stores MULT result
                        int tempReg2 = NextRegister();  // stores final address
                        int tempReg3 = NextRegister();  // return register
                        int tempReg4 = NextRegister();  // stores 4
                        int tempReg5 = NextRegister();  // stores baseOffset
                        int tempReg6 = NextRegister();  // stores first add
                        $$.targetRegister = tempReg3;

                        sprintf(CommentBuffer, "Multiply index by 4");
                        emitComment(CommentBuffer);
                        emit(NOLABEL, LOADI, 4, tempReg4, EMPTY);
                        emit(NOLABEL, MULT, indexReg, tempReg4, tempReg1);

                        sprintf(CommentBuffer, "Compute address of array element");
                        emitComment(CommentBuffer);
                        emit(NOLABEL, LOADI, baseOffset, tempReg5, EMPTY);
                        emit(NOLABEL, ADD, 0, tempReg5, tempReg6);
                        emit(NOLABEL, ADD, tempReg6, tempReg1, tempReg2);

                        // we have to actually load the value for this rule
                        emit(NOLABEL, LOAD, tempReg2, tempReg3, EMPTY);
                }

        }


        | '(' exp ')'           { $$.targetRegister = $2.targetRegister; }


	| constant                { int newReg = NextRegister();
	                          $$.targetRegister = newReg;
	                          emit(NOLABEL, LOADI, $1.num, newReg, EMPTY); }

	| error { yyerror("***Error: illegal expression\n");}  
	;

condexp	: exp NEQ exp	{ int newReg = NextRegister();
                          $$.targetRegister = newReg;
                          condGlobal.targetRegister = newReg;
                          emit(NOLABEL, CMPNE, $1.targetRegister, $3.targetRegister, newReg);
                        }
	| exp EQ exp	{ int newReg = NextRegister();
                          $$.targetRegister = newReg;
                          condGlobal.targetRegister = newReg;
                          emit(NOLABEL, CMPEQ, $1.targetRegister, $3.targetRegister, newReg);
                        }
	| exp LT exp	{ int newReg = NextRegister();
                          $$.targetRegister = newReg;
                          condGlobal.targetRegister = newReg;
                          emit(NOLABEL, CMPLT, $1.targetRegister, $3.targetRegister, newReg);
                        }
	| exp LEQ exp	{ int newReg = NextRegister();
                          $$.targetRegister = newReg;
                          condGlobal.targetRegister = newReg;
                          emit(NOLABEL, CMPLE, $1.targetRegister, $3.targetRegister, newReg);
                        }

        | ID            { int offset = getOffset($1.str);

                          if(offset == -1) {
                                sprintf(CommentBuffer, "ERROR: variable %s is not declared", $1.str);
                                yyerror(CommentBuffer);
                          } else {
                                int newReg = NextRegister();
                                $$.targetRegister = newReg;
                                condGlobal.targetRegister = newReg;
                                emit(NOLABEL, LOADAI, 0, offset, newReg);
                          }
                        }

        | boolean_constant { int newReg = NextRegister();
                             $$.targetRegister = newReg;
                             condGlobal.targetRegister = newReg;
                             emit(NOLABEL, LOADI, $1.num, newReg, EMPTY);
                           }

	| error { yyerror("***Error: illegal conditional expression\n");}  
        ;

constant : integer_constant { $$.num = $1.num; }
         | boolean_constant { $$.num = $1.num; }
         ;

integer_constant : ICONST { $$.num = $1.num; }
                 ;

boolean_constant : TRUE         { $$.num = 1; }
                 | FALSE        { $$.num = 0; }
                 ;

%%

void yyerror(char* s) {
        fprintf(stderr,"%s\n",s);
	fflush(stderr);
        }

int
main() {
  printf("\n          CS415 Project 2: Code Generator\n\n");
  
  outfile = fopen("iloc.out", "w");
  if (outfile == NULL) { 
    printf("ERROR: cannot open output file \"iloc.out\".\n");
    return -1;
  }

  CommentBuffer = (char *) malloc(500); 

  initSymtab(); 

  printf("1\t");
  yyparse();
  printf("\n");  

  fclose(outfile);
  
  return 1;
}




