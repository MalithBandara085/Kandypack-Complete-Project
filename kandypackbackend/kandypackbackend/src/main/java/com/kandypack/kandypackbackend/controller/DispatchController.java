package com.kandypack.kandypackbackend.controller;

import com.kandypack.kandypackbackend.entity.TruckDispatch;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

@RestController
@RequestMapping("/api/dispatches")
public class DispatchController {

    @Autowired
    private TruckDispatchRepo truckDispatchRepo;

    @GetMapping
    public List<TruckDispatch> getAllDispatches() {
        return truckDispatchRepo.findAll();
    }

    @GetMapping("/{id}")
    public ResponseEntity<TruckDispatch> getDispatchById(@PathVariable String id) {
        return truckDispatchRepo.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }
}

interface TruckDispatchRepo extends JpaRepository<TruckDispatch, String> {
}