/**********************************************
        CS415  Compilers  Project 2
**********************************************/

#include <stdio.h>
#include <string.h>
#include "symtab.h"

// NOTE: I removed the unnecessary declaration of malloc() below
// extern void * malloc(int size);

// Static symbol array
Symbol symtab[MAX_SYMBOLS];

// Stack
int labelStack[LABEL_STACK_SIZE];
int labelTop = -1;

int symbolCount = 0;
int nextOffset = 1024;

// Initializes the symbol table with a count of 0
// starting at address 1024
void initSymtab() {
        symbolCount = 0;
        nextOffset = 0;
}

// Inserts a new symbol into the table
int insert(char *name, int type) {
        // First we check if the symbol has been entered already
        for(int i = 0; i < symbolCount; i++) {
                if(strcmp(symtab[i].name, name) == 0) {
                        return -1;
                }
        }

        // Otherwise, we add the symbol to the table
        strcpy(symtab[symbolCount].name, name);
        symtab[symbolCount].type = type;
        symtab[symbolCount].offset = nextOffset;

        // Increment (This project only contains ints and 4-byte bools)
        nextOffset += 4;
        symbolCount ++;
        
        return 0;
}

int insert_array(char *name, int type, int lowBound, int highBound) {
        // Check if it is in the table
        for(int i = 0; i < symbolCount; i++) {
                if(strcmp(symtab[i].name, name) == 0) {
                        return -1;
                }
        }

        // calculate array size in bytes
        int arraySize = (highBound - lowBound + 1) * 4;

        // insert the new symbol into the table
        strcpy(symtab[symbolCount].name, name);
        symtab[symbolCount].type = type;
        symtab[symbolCount].offset = nextOffset;
        symtab[symbolCount].lowBound = lowBound;
        symtab[symbolCount].highBound = highBound;
        symtab[symbolCount].arraySize = arraySize;

        // increment offset and symbolCount
        nextOffset += arraySize;
        symbolCount++;

        return 0;
}

// Loop over symtab and find matching name
// Returns index if found
int lookup(char *name) {
        for(int i = 0; i < symbolCount; i++) {
                if(strcmp(symtab[i].name, name) == 0) {
                        return i;
                }
        }

        return -1;
}

// Lookup name and return offset field
int getOffset(char *name) {
        int index = lookup(name);
        
        if(index >= 0) {
                //printf("OFFSET: %d\n", symtab[index].offset);
                return symtab[index].offset;
        }

        return -1;
}

void push_label(int label) {
        labelTop++;
        labelStack[labelTop] = label;
}

int pop_label() {
        int label = labelStack[labelTop];
        labelTop--;
        return label;
}

