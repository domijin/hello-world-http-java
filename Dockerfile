FROM openjdk:8-jre-alpine
COPY HelloWorld.jar .
EXPOSE 8000

## Run the Java application
ENTRYPOINT ["java", "-jar", "HelloWorld.jar"]