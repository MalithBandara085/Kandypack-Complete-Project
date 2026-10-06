package com.kandypack.kandypackbackend.repository;

import com.kandypack.kandypackbackend.entity.OrderTravel;
import com.kandypack.kandypackbackend.entity.OrderTravelId;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OrderTravelRepo extends JpaRepository<OrderTravel, OrderTravelId> {
}