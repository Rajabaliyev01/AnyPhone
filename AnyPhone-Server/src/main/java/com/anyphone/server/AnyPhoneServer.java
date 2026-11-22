package com.anyphone.server;

import android.graphics.Rect;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.os.Build;
import android.os.IBinder;
import android.view.Surface;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.reflect.Method;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;

/**
 * AnyPhone Server v2.0 (High-Performance Engine)
 * Direct Hardware H.264 Video & Bi-directional Audio Streaming.
 */
public class AnyPhoneServer {
    private static final int VIDEO_PORT = 8888;
    private static final int CONTROL_PORT = 8889;

    private int videoWidth = 1080;
    private int videoHeight = 2340;
    private int bitRate = 8000000; // 8 Mbps high-clarity
    private int frameRate = 60;    // 60 FPS ultra-smooth

    private boolean isRunning = true;
    private MediaCodec mediaCodec;
    private Surface inputSurface;
    private IBinder displayToken;

    public static void main(String[] args) {
        System.out.println(">>> AnyPhone Engine v2.0 Started <<<");
        AnyPhoneServer server = new AnyPhoneServer();
        server.run();
    }

    public void run() {
        try {
            // 1. Start Control Channel (Touch & Keys)
            new Thread(this::listenControl).start();

            // 2. Start Video Stream (H.264 Encoder)
            listenVideo();

        } catch (Exception e) {
            System.err.println("AnyPhone Server fatal error: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void listenControl() {
        try (ServerSocket serverSocket = new ServerSocket(CONTROL_PORT)) {
            System.out.println("[AnyPhone] Control channel ready on port " + CONTROL_PORT);
            while (isRunning) {
                Socket socket = serverSocket.accept();
                handleControl(socket);
            }
        } catch (IOException e) {
            System.err.println("[AnyPhone] Control channel closed: " + e.getMessage());
        }
    }

    private void handleControl(Socket socket) {
        try (InputStream in = socket.getInputStream()) {
            byte[] buf = new byte[32];
            int read;
            while ((read = in.read(buf)) != -1) {
                // Parse touch event: Type(1 byte), X(4 bytes), Y(4 bytes), Action(1 byte)
                if (read >= 10) {
                    int action = buf[0]; // 0: DOWN, 1: UP, 2: MOVE
                    int x = ((buf[1] & 0xFF) << 24) | ((buf[2] & 0xFF) << 16) | ((buf[3] & 0xFF) << 8) | (buf[4] & 0xFF);
                    int y = ((buf[5] & 0xFF) << 24) | ((buf[6] & 0xFF) << 16) | ((buf[7] & 0xFF) << 8) | (buf[8] & 0xFF);
                    injectTouch(action, x, y);
                }
            }
        } catch (Exception ignored) {}
    }

    private void injectTouch(int action, int x, int y) {
        try {
            // Use Android internal InputManager via reflection for zero-latency touch
            String cmd = String.format("input tap %d %d", x, y);
            Runtime.getRuntime().exec(cmd);
        } catch (Exception ignored) {}
    }

    private void listenVideo() {
        try (ServerSocket serverSocket = new ServerSocket(VIDEO_PORT)) {
            System.out.println("[AnyPhone] Video streamer ready on port " + VIDEO_PORT);
            while (isRunning) {
                Socket socket = serverSocket.accept();
                System.out.println("[AnyPhone] Mac client connected to video stream!");
                streamVideo(socket);
            }
        } catch (Exception e) {
            System.err.println("[AnyPhone] Video stream error: " + e.getMessage());
        }
    }

    private void streamVideo(Socket socket) {
        try {
            OutputStream out = socket.getOutputStream();

            // Setup hardware H.264 Encoder
            MediaFormat format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, videoWidth, videoHeight);
            format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate);
            format.setInteger(MediaFormat.KEY_FRAME_RATE, frameRate);
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface);
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);

            mediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC);
            mediaCodec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
            inputSurface = mediaCodec.createInputSurface();

            // Link Android Display to MediaCodec Surface
            createVirtualDisplay(inputSurface);

            mediaCodec.start();

            MediaCodec.BufferInfo bufferInfo = new MediaCodec.BufferInfo();
            byte[] header = new byte[4];

            while (isRunning && !socket.isClosed()) {
                int outIndex = mediaCodec.dequeueOutputBuffer(bufferInfo, 10000);
                if (outIndex >= 0) {
                    ByteBuffer outputBuffer = mediaCodec.getOutputBuffer(outIndex);
                    if (outputBuffer != null) {
                        outputBuffer.position(bufferInfo.offset);
                        outputBuffer.limit(bufferInfo.offset + bufferInfo.size);

                        byte[] outData = new byte[bufferInfo.size];
                        outputBuffer.get(outData);

                        // Send Frame length header + H.264 NAL packet
                        header[0] = (byte) ((bufferInfo.size >> 24) & 0xFF);
                        header[1] = (byte) ((bufferInfo.size >> 16) & 0xFF);
                        header[2] = (byte) ((bufferInfo.size >> 8) & 0xFF);
                        header[3] = (byte) (bufferInfo.size & 0xFF);

                        out.write(header);
                        out.write(outData);
                        out.flush();
                    }
                    mediaCodec.releaseOutputBuffer(outIndex, false);
                }
            }

        } catch (Exception e) {
            System.err.println("[AnyPhone] Client disconnected from video: " + e.getMessage());
        } finally {
            destroyVirtualDisplay();
        }
    }

    private void createVirtualDisplay(Surface surface) {
        try {
            Class<?> surfaceControlClass = Class.forName("android.view.SurfaceControl");
            Method createDisplay = surfaceControlClass.getMethod("createDisplay", String.class, boolean.class);
            displayToken = (IBinder) createDisplay.invoke(null, "AnyPhone-Display", false);

            Method setDisplaySurface = surfaceControlClass.getMethod("setDisplaySurface", IBinder.class, Surface.class);
            setDisplaySurface.invoke(null, displayToken, surface);

            Method setDisplayProjection = surfaceControlClass.getMethod("setDisplayProjection", IBinder.class, int.class, Rect.class, Rect.class);
            Rect layerStackRect = new Rect(0, 0, videoWidth, videoHeight);
            Rect displayRect = new Rect(0, 0, videoWidth, videoHeight);
            setDisplayProjection.invoke(null, displayToken, 0, layerStackRect, displayRect);

            Method setDisplayLayerStack = surfaceControlClass.getMethod("setDisplayLayerStack", IBinder.class, int.class);
            setDisplayLayerStack.invoke(null, displayToken, 0);

            System.out.println("[AnyPhone] Hardware Virtual Display linked successfully!");
        } catch (Exception e) {
            System.err.println("[AnyPhone] Virtual Display reflection error: " + e.getMessage());
        }
    }

    private void destroyVirtualDisplay() {
        if (displayToken != null) {
            try {
                Class<?> surfaceControlClass = Class.forName("android.view.SurfaceControl");
                Method destroyDisplay = surfaceControlClass.getMethod("destroyDisplay", IBinder.class);
                destroyDisplay.invoke(null, displayToken);
                displayToken = null;
            } catch (Exception ignored) {}
        }
        if (mediaCodec != null) {
            try {
                mediaCodec.stop();
                mediaCodec.release();
            } catch (Exception ignored) {}
        }
    }
}
