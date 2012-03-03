OBJS=main.o
CC=g++
CFLAGS=-O3
name=longest_string

all: main.cpp
	 $(CC) $(CFLAGS) -o $(name) main.cpp

clean:
	rm -fr *~ $(name) $(OBJS)
