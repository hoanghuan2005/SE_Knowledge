package com.fe_knowledge.backend.exception;

import org.springframework.http.HttpStatus;

/**
 * Ngoại lệ ném ra khi không tìm thấy tài nguyên theo ID hoặc điều kiện tìm kiếm.
 */
public class ResourceNotFoundException extends ApiException {

    public ResourceNotFoundException(String resourceName, String fieldName, Object fieldValue) {
        super(String.format("Không tìm thấy %s với %s: '%s'", resourceName, fieldName, fieldValue), HttpStatus.NOT_FOUND);
    }

    public ResourceNotFoundException(String message) {
        super(message, HttpStatus.NOT_FOUND);
    }
}
