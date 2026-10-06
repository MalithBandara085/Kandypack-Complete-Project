package com.kandypack.kandypackbackend.repository;

import com.kandypack.kandypackbackend.entity.StaffUser;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface StaffUserRepo extends JpaRepository<StaffUser, String> {
    Optional<StaffUser> findByEmail(String email);
}