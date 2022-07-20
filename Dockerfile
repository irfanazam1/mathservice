FROM openjdk:17-alpine
MAINTAINER irfanazam1@github.com
ARG JAR_FILE=target/*.jar
COPY ${JAR_FILE} mathservice-0.0.1-SNAPSHOT.jar
ENTRYPOINT ["java","-jar","/mathservice-0.0.1-SNAPSHOT.jar"]