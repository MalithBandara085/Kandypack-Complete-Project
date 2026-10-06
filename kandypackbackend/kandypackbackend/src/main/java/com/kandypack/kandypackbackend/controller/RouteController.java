package com.kandypack.kandypackbackend.controller;

import com.kandypack.kandypackbackend.entity.Route;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

@RestController
@RequestMapping("/api/routes")
public class RouteController {

    @Autowired
    private RouteRepo routeRepo;

    @GetMapping
    public List<Route> getAllRoutes() {
        return routeRepo.findAll();
    }

    @GetMapping("/{id}")
    public ResponseEntity<Route> getRouteById(@PathVariable String id) {
        return routeRepo.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }
}

interface RouteRepo extends JpaRepository<Route, String> {
}