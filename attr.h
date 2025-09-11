/**********************************************
			 CS415 Compilers Project 2
**********************************************/

#ifndef ATTR_H
#define ATTR_H

typedef union {int num; char *str;} tokentype;

typedef struct {  
        int targetRegister;
        } regInfo;

typedef struct {
        int num;        // "num" is regular type info, the other fields are array info
        int arrayType;
        int lowBound;
        int highBound;
} typeInfo;

typedef struct {
        char **idList;
} idListInfo;

#endif