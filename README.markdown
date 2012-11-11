# 4917 Longest String

## Basic Instructions

To get ready for development and compile the code run:

    bash scripts/setup_development.bash

And that is all. This should setup everything for you and compile the code too. Just look
at what the script is actually doing to get a better idea of how to compile the code.

## Goal

The aim of this project is to create a Client / Server networking model that can solve this problem
as efficiently as possible and with as few machines as possible. The problem is to come up with the
longest string for any given program that can be emulated on that machine at any given level.

## Purpose

To see all of the cool programs that come out of this exploration and to actually say that I did it.

## Minor Goals

 - Stateful (Must be able to save / load server state in the event of a server shutdown or backup)
 - Must be able to delegate work quickly and efficiently.
 - Must be correct! There is absolutely no point doing this if it is not correct.

## Dependancies

This code requires:

 - Boost (Version 1.4.7 or higher)
