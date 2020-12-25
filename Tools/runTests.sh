#!/bin/csh

# Run this from the root of the project-- i.e., where the Package.swift file is.

cp TestDataFiles/example.url /tmp
cp TestDataFiles/Cat.jpg /tmp
swift test
