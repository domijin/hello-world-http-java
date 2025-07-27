#!/bin/bash
echo "Building Java application..."
javac HelloWorld.java
jar cvfe HelloWorld.jar HelloWorld *.class
echo "Build complete! Run with: java -jar HelloWorld.jar"