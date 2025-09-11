/**********************************************
        CS415  Compilers  Project 2
**********************************************/

#ifndef SYMTAB_H
#define SYMTAB_H

// We can have a maximum of 1024 symbols
// Each data type has it's own macro 
#define MAX_SYMBOLS 1024
#define LABEL_STACK_SIZE 64
#define TYPE_INT 1
#define TYPE_BOOL 2
#define TYPE_ARRAY 3

// Symbol struct containing name, type, and offset
typedef struct {
        char name[64];
        int type;
        int offset;
        int lowBound;
        int highBound;
        int arraySize;
} Symbol;

// Functions to be called in parse.y
void initSymtab();
int insert(char *name, int type);
int insert_array(char *name, int type, int lowBound, int highBound);
int lookup(char *name);
int getOffset(char *name);

// Stack functions
void push_label(int label);
int pop_label();

#endif
