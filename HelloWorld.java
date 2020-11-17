import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

public class HelloWorld {
    public static void main(String[] args) throws Exception {
        final int port = 8000;
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);
        server.createContext("/", new MyHandler());
        server.setExecutor(null); // creates a default executor
        System.out.println("Serving on port 8000..\n");
        server.start();
    } 

    static class MyHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange t) throws IOException {
            // Logging IP address of request to stdout
            System.out.println("Request received from: " + t.getRemoteAddress().toString());

            // Displaying Hello message
            String hello = "Hello CBSA!!!!!!";
            String response = "<html><body><h1>" + hello + "</h1>\n";

            // Displaying the OS arch that this is running on
            response += "<h2>JVM Architecture: " + System.getProperty("os.arch") + "</h2>\n";
            
            response += "<h2>JVM Flavor: " + System.getProperty("java.vm.name") + " "  + System.getProperty("java.version") + "</h2>\n";
            response += "</ul></body></html>\n";

            // Sending response
            t.sendResponseHeaders(200, response.length());
            OutputStream os = t.getResponseBody();
            os.write(response.getBytes());
            os.close();
        }
    }
}
