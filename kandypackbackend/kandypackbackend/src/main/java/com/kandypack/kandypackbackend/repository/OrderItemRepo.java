package com.kandypack.kandypackbackend.repository;

import com.kandypack.kandypackbackend.entity.OrderItem;
import com.kandypack.kandypackbackend.entity.OrderItemId;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OrderItemRepo extends JpaRepository<OrderItem, OrderItemId> {
}