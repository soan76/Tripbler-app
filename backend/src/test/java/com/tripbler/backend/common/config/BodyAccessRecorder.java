package com.tripbler.backend.common.config;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.Collection;
import java.util.Enumeration;
import java.util.Map;
import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.atomic.AtomicLong;

import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.Part;

/**
 * 가장 앞의 서블릿 필터에서 요청을 감싸 본문 접근을 기록한다(본문 내용은 기록하지 않음).
 *
 * <p>파트·파라미터 접근(getParts, getPart, getParameter*)과 본문 스트림 접근(getInputStream, getReader)을
 * 기록하고, 스트림으로 읽은 바이트 수를 센다. Tomcat의 multipart 해석은 파트·파라미터 접근으로만, 그 밖의 본문
 * 읽기(FormContentFilter, 핸들러의 @RequestBody)는 스트림 접근으로만 일어나므로 기록이 없으면 읽지 않은 것이다.
 */
class BodyAccessRecorder {

    final Queue<String> accesses = new ConcurrentLinkedQueue<>();
    final AtomicLong bytesRead = new AtomicLong();

    void clear() {
        accesses.clear();
        bytesRead.set(0);
    }

    HttpServletRequest wrap(HttpServletRequest request) {
        return new HttpServletRequestWrapper(request) {
            @Override
            public Collection<Part> getParts() throws IOException, ServletException {
                accesses.add("getParts " + request.getRequestURI());
                return super.getParts();
            }

            @Override
            public Part getPart(String name) throws IOException, ServletException {
                accesses.add("getPart " + request.getRequestURI());
                return super.getPart(name);
            }

            @Override
            public String getParameter(String name) {
                accesses.add("getParameter " + request.getRequestURI());
                return super.getParameter(name);
            }

            @Override
            public Map<String, String[]> getParameterMap() {
                accesses.add("getParameterMap " + request.getRequestURI());
                return super.getParameterMap();
            }

            @Override
            public Enumeration<String> getParameterNames() {
                accesses.add("getParameterNames " + request.getRequestURI());
                return super.getParameterNames();
            }

            @Override
            public String[] getParameterValues(String name) {
                accesses.add("getParameterValues " + request.getRequestURI());
                return super.getParameterValues(name);
            }

            @Override
            public ServletInputStream getInputStream() throws IOException {
                accesses.add("getInputStream " + request.getRequestURI());
                return new CountingInputStream(super.getInputStream());
            }

            @Override
            public BufferedReader getReader() throws IOException {
                accesses.add("getReader " + request.getRequestURI());
                String encoding = getCharacterEncoding();
                return new BufferedReader(new InputStreamReader(
                    new CountingInputStream(super.getInputStream()),
                    encoding != null ? Charset.forName(encoding) : StandardCharsets.ISO_8859_1));
            }
        };
    }

    /** 읽은 바이트 수를 bytesRead에 더한다. */
    private class CountingInputStream extends ServletInputStream {
        private final ServletInputStream delegate;

        CountingInputStream(ServletInputStream delegate) {
            this.delegate = delegate;
        }

        @Override
        public int read() throws IOException {
            int value = delegate.read();
            if (value >= 0) {
                bytesRead.incrementAndGet();
            }
            return value;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) throws IOException {
            int count = delegate.read(buffer, offset, length);
            if (count > 0) {
                bytesRead.addAndGet(count);
            }
            return count;
        }

        @Override
        public boolean isFinished() {
            return delegate.isFinished();
        }

        @Override
        public boolean isReady() {
            return delegate.isReady();
        }

        @Override
        public void setReadListener(ReadListener listener) {
            delegate.setReadListener(listener);
        }
    }
}
