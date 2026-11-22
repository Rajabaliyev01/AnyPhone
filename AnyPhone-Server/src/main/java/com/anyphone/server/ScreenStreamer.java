package com.anyphone.server;

import android.graphics.Rect;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.os.IBinder;
import android.view.Surface;

import java.io.OutputStream;
import java.lang.reflect.Method;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;

/**
 * ScreenStreamer
 * Captures Android display via Hardware MediaCodec (H.264 / AVC)
 * Streams NAL units to Mac Metal / VideoToolbox decoder at 60 FPS.
 */
public class ScreenStreamer implements Runnable {
    private static final int PORT = 8888;
    private final int width = 1080;
    private final int height = 2340;
    private final int bitRate = 8000000; // 8 Mbps
    private final int frameRate = 60;

    private boolean isRunning = true;
    private MediaCodec codec;
    private IBinder displayToken;

    @Override
    public void run() {
        try (ServerSocket serverSocket = new ServerSocket(PORT)) {
            System.out.println("[ScreenStreamer] Listening on port " + PORT);
            while (isRunning) {
                Socket client = serverSocket.accept();
                System.out.println("[ScreenStreamer] Mac connected to hardware video stream!");
                handleStream(client);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void handleStream(Socket socket) {
        try {
            OutputStream out = socket.getOutputStream();

            MediaFormat format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height);
            format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate);
            format.setInteger(MediaFormat.KEY_FRAME_RATE, frameRate);
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface);
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);

            codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC);
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
            Surface surface = codec.createInputSurface();

            // Link Android Display to MediaCodec Surface
            createVirtualDisplay(surface);
            codec.start();

            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            byte[] header = new byte[4];

            while (isRunning && !socket.isClosed()) {
                int index = codec.dequeueOutputBuffer(info, 10000);
                if (index >= 0) {
                    ByteBuffer buffer = codec.getOutputBuffer(index);
                    if (buffer != null) {
                        buffer.position(info.offset);
                        buffer.limit(info.offset + info.size);

                        byte[] outBytes = new byte[info.size];
                        buffer.get(outBytes);

                        // 4-byte length header + H.264 frame
                        header[0] = (byte) ((info.size >> 24) & 0xFF);
                        header[1] = (byte) ((info.size >> 16) & 0xFF);
                        header[2] = (byte) ((info.size >> 8) & 0xFF);
                        header[3] = (byte) (info.size & 0xFF);

                        out.write(header);
                        out.write(outBytes);
                        out.flush();
                    }
                    codec.releaseOutputBuffer(index, false);
                }
            }
        } catch (Exception e) {
            System.err.println("[ScreenStreamer] Stream closed: " + e.getMessage());
        } finally {
            cleanup();
        }
    }

    private void createVirtualDisplay(Surface surface) {
        try {
            Class<?> sc = Class.forName("android.view.SurfaceControl");
            Method createDisplay = sc.getMethod("createDisplay", String.class, boolean.class);
            displayToken = (IBinder) createDisplay.invoke(null, "AnyPhone-Display", false);

            Method setSurface = sc.getMethod("setDisplaySurface", IBinder.class, Surface.class);
            setSurface.invoke(null, displayToken, surface);

            Method setProj = sc.getMethod("setDisplayProjection", IBinder.class, int.class, Rect.class, Rect.class);
            Rect rect = new Rect(0, 0, width, height);
            setProj.invoke(null, displayToken, 0, rect, rect);

            Method setStack = sc.getMethod("setDisplayLayerStack", IBinder.class, int.class);
            setStack.invoke(null, displayToken, 0);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void cleanup() {
        if (displayToken != null) {
            try {
                Class<?> sc = Class.forName("android.view.SurfaceControl");
                Method destroy = sc.getMethod("destroyDisplay", IBinder.class);
                destroy.invoke(null, displayToken);
                displayToken = null;
            } catch (Exception ignored) {}
        }
        if (codec != null) {
            try {
                codec.stop();
                codec.release();
            } catch (Exception ignored) {}
        }
    }
}
