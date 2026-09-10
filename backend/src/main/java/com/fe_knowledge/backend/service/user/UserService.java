package com.fe_knowledge.backend.service.user;

import com.fe_knowledge.backend.dto.request.UserRequest;
import com.fe_knowledge.backend.dto.response.UserResponse;

import java.util.List;

/**
 * Interface định nghĩa các nghiệp vụ liên quan đến User.
 */
public interface UserService {

    List<UserResponse> getAllUsers();

    UserResponse getUserById(Long id);

    UserResponse createUser(UserRequest request);

    void deleteUser(Long id);
}
