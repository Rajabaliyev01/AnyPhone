package com.anyphone.server;

import java.io.InputStream;
import java.net.ServerSocket;
import java.net.Socket;

/**
 * InputController
 * Receives touch, drag, swipe, and key events from macOS client.
 */
public class InputController implements Runnable {
    private static final int CONTROL_PORT = 8890;
    private boolean isRunning = true;

    @Override
    public void run() {
        try (ServerSocket serverSocket = new ServerSocket(CONTROL_PORT)) {
            System.out.println("[InputController] Listening on port " + CONTROL_PORT);
            while (isRunning) {
                Socket socket = serverSocket.accept();
                handleInput(socket);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void handleInput(Socket socket) {
        try (InputStream in = socket.getInputStream()) {
            byte[] buf = new byte[64];
            int read;
            while ((read = in.read(buf)) != -1) {
                String cmd = new String(buf, 0, read).trim();
                if (cmd.startsWith("TAP")) {
                    String[] parts = cmd.split(" ");
                    if (parts.length >= 3) {
                        Runtime.getRuntime().exec("input tap " + parts[1] + " " + parts[2]);
                    }
                } else if (cmd.startsWith("SWIPE")) {
                    String[] parts = cmd.split(" ");
                    if (parts.length >= 5) {
                        Runtime.getRuntime().exec("input swipe " + parts[1] + " " + parts[2] + " " + parts[3] + " " + parts[4] + " 150");
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
