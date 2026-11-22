package com.anyphone.server;

/**
 * AnyPhone Server Main Entry Point
 */
public class AnyPhoneServer {
    public static void main(String[] args) {
        System.out.println(">>> AnyPhone Server v2.0 Engine Initializing <<<");
        new Thread(new ScreenStreamer()).start();
        new Thread(new AudioBridge()).start();
        new Thread(new InputController()).start();
    }
}
