#!/bin/bash
javac HelloWorld.java &&
jar cmvf META-INF/MANIFEST.MF HelloWorld.jar *.class &&
java -jar HelloWorld.jar