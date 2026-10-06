package com.kandypack.kandypackbackend.repository;

import com.kandypack.kandypackbackend.entity.Customer;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface CustomerRepo extends JpaRepository<Customer, String> {
    Optional<Customer> findByEmail(String email);
}