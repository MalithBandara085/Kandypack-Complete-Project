package com.kandypack.kandypackbackend.repository;

import com.kandypack.kandypackbackend.entity.Product;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProductRepo extends JpaRepository<Product, String> {
}