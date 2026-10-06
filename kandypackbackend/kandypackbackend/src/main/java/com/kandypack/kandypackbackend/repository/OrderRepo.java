package com.kandypack.kandypackbackend.repository;

import com.kandypack.kandypackbackend.entity.CustomerOrder;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OrderRepo extends JpaRepository<CustomerOrder, String> {
}