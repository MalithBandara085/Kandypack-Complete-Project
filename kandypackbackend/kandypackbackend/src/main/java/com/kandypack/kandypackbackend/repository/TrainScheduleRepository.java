package com.kandypack.kandypackbackend.repository;

import com.kandypack.kandypackbackend.entity.TrainSchedule;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface TrainScheduleRepository extends JpaRepository<TrainSchedule, String> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT t FROM TrainSchedule t WHERE t.tripId = :tripId")
    Optional<TrainSchedule> findByIdForUpdate(@Param("tripId") String tripId);
}