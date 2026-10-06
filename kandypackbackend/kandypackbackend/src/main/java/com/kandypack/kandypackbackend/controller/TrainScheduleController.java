package com.kandypack.kandypackbackend.controller;

import com.kandypack.kandypackbackend.entity.TrainSchedule;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

@RestController
@RequestMapping("/api/trains")
public class TrainScheduleController {

    @Autowired
    private TrainScheduleRepo trainScheduleRepo;

    @GetMapping
    public List<TrainSchedule> getAllTrips() {
        return trainScheduleRepo.findAll();
    }

    @GetMapping("/{id}")
    public ResponseEntity<TrainSchedule> getTripById(@PathVariable String id) {
        return trainScheduleRepo.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }
}

interface TrainScheduleRepo extends JpaRepository<TrainSchedule, String> {
}