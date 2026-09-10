package com.fe_knowledge.backend.exception;

import lombok.Getter;
import org.springframework.http.HttpStatus;

/**
 * Base Runtime Exception cho các lỗi nghiệp vụ trong hệ thống.
 */
@Getter
public class ApiException extends RuntimeException {

    private final HttpStatus status;

    public ApiException(String message) {
        super(message);
        this.status = HttpStatus.BAD_REQUEST;
    }

    public ApiException(String message, HttpStatus status) {
        super(message);
        this.status = status;
    }
}
