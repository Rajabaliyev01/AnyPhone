package com.anyphone.server;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;

/**
 * AnyPhone Server Engine
 * Lightweight, high-performance screen & control bridge for Android.
 */
public class AnyPhoneServer {
    private static final int PORT = 8888;
    private boolean running = true;

    public static void main(String[] args) {
        System.out.println(">>> AnyPhone Engine Started on Android <<<");
        new AnyPhoneServer().start();
    }

    public void start() {
        try (ServerSocket serverSocket = new ServerSocket(PORT)) {
            System.out.println("AnyPhone Server listening on port " + PORT);
            while (running) {
                Socket socket = serverSocket.accept();
                new Thread(() -> handleClient(socket)).start();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void handleClient(Socket socket) {
        try {
            InputStream in = socket.getInputStream();
            OutputStream out = socket.getOutputStream();

            byte[] buffer = new byte[64];
            int read;
            while ((read = in.read(buffer)) != -1) {
                String cmd = new String(buffer, 0, read).trim();
                if (cmd.startsWith("TAP")) {
                    // Execute touch
                    String[] parts = cmd.split(" ");
                    if (parts.length >= 3) {
                        Runtime.getRuntime().exec("input tap " + parts[1] + " " + parts[2]);
                    }
                } else if (cmd.startsWith("SWIPE")) {
                    // Execute swipe
                    String[] parts = cmd.split(" ");
                    if (parts.length >= 5) {
                        Runtime.getRuntime().exec("input swipe " + parts[1] + " " + parts[2] + " " + parts[3] + " " + parts[4] + " 250");
                    }
                } else if (cmd.startsWith("KEY")) {
                    String[] parts = cmd.split(" ");
                    if (parts.length >= 2) {
                        Runtime.getRuntime().exec("input keyevent " + parts[1]);
                    }
                }
            }
        } catch (Exception ignored) {}
    }
}
