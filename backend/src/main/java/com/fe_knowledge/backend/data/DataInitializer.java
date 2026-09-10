package com.fe_knowledge.backend.data;

import com.fe_knowledge.backend.entity.User;
import com.fe_knowledge.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

/**
 * Khởi tạo dữ liệu mẫu khi ứng dụng khởi chạy lần đầu.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class DataInitializer implements CommandLineRunner {

    private final UserRepository userRepository;

    @Override
    public void run(String... args) {
        if (userRepository.count() == 0) {
            log.info("Chưa có dữ liệu người dùng, tiến hành tạo tài khoản Admin và User mặc định...");

            User admin = User.builder()
                    .email("admin@fe_knowledge.com")
                    .fullName("System Administrator")
                    .role("ADMIN")
                    .build();

            User student = User.builder()
                    .email("student@fpt.edu.vn")
                    .fullName("FPT SE Student")
                    .role("STUDENT")
                    .build();

            userRepository.save(admin);
            userRepository.save(student);

            log.info("Khởi tạo dữ liệu mẫu thành công!");
        }
    }
}
