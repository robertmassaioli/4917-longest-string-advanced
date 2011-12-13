OBJS = main.o
CC = g++
CFLAGS = –03
name=longest_string

all : $(OBJS)
	 $(CC) -o $(name) $(OBJS)

.c.o:
	$(CC) -c $(CFLAGS) $(.SOURCE)
	
clean:
	rm -fr *~ $(name) $(OBJS)
