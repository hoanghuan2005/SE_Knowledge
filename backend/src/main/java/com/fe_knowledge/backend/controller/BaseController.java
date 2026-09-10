package com.fe_knowledge.backend.controller;

import com.fe_knowledge.backend.dto.ApiResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

/**
 * Base Controller cung cấp các phương thức tiện ích trả về ResponseEntity chuẩn cho toàn bộ Controller.
 */
public abstract class BaseController {

    protected <T> ResponseEntity<ApiResponse<T>> ok(T data) {
        return ResponseEntity.ok(ApiResponse.success(data));
    }

    protected <T> ResponseEntity<ApiResponse<T>> ok(T data, String message) {
        return ResponseEntity.ok(ApiResponse.success(data, message));
    }

    protected <T> ResponseEntity<ApiResponse<T>> created(T data, String message) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.success(data, message));
    }

    protected ResponseEntity<ApiResponse<Void>> noContent() {
        return ResponseEntity.status(HttpStatus.NO_CONTENT).build();
    }
}
