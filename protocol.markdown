# Communication Protocol

This describes the communication protocol that the clients and servers use to talk to one
another. This is very important as it decides the speed of the entire protocol. By default
we should be using the absolute smallest number of bytes that we possibly can.

The communication protocol works via a bunch of messages. Every message leads with a one
byte type followed by custom message data.

Message Types from client to server are:

1 - Requesting X tasks.
2 - Posting back data for task X.
3 - Keep Alive Ping with progress X on task Y.

Message Types from server to client are:

1 - Sending X tasks to add to backlog.
3 - Requesting Keep Alive Ping.

Each of these different protocols needs to be defined and the messages sent need to be
compiled. We will also want a shorthand to refer to the message type, therefore, if it is
message type one from the client then we call it C1 and if it is message type 3 from the
server then we call it S3. This is the pattern that we will follow.

Everything that is not of the supported message types is an error and any connection that
sends them should be immediately terminated with the reason printed out to some sort of
error logging.

C1 should just contain a number that is the number of tasks that it wishes to obtain.
S1 should contain a range that specifies the tasks that have been assigned to this client.
C2 is complicated and will be given a better description below.
C3 should send back two numbers. The first number should be the current task that it is
working on and the second number should be how far it is through that task. In other
words, it should send back the exact program that it is working on right now. That way we
can see the problems progress on a monitor back on the server side.
S3 should have no data, it is a request for data. This should never actually need to be
used since the client is supposed to send this back in regular intervals anyway.

I don't think that there should be a lock in the client code, we should do everything we
possibly can to avoid locking. I don't even care if that means that our progress is off a
little bit. The progress meter is a nicety but the speed of the client is critical.

As mentioned before C2 is the most complex message that will be sent. It needs to send
back the results for every different program length. For each program length it needs
to send back:

 - The longest program
 - The length of that program.

To which the server will verify locally. The server should always verify every result to
prevent againt one form of cheating. Ideally we would prevent against other forms of
cheating but that may prove to be difficult. To prevent against other forms of cheating it
would be good to have an audit log of every client that worked on the tasks and
which tasks they completed.
