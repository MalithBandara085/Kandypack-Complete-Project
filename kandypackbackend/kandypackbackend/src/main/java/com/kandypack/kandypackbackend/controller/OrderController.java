package com.kandypack.kandypackbackend.controller;

import com.kandypack.kandypackbackend.dto.OrderRequest;
import com.kandypack.kandypackbackend.dto.OrderResponse;
import com.kandypack.kandypackbackend.entity.CustomerOrder;
import com.kandypack.kandypackbackend.service.OrderAssignmentService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.data.jpa.repository.JpaRepository;
import jakarta.validation.Valid;
import java.util.List;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    @PutMapping("/{id}/status")
    @org.springframework.security.access.prepost.PreAuthorize("hasAnyRole('ADMIN', 'DISPATCHER', 'DRIVER')")
    public ResponseEntity<?> updateOrderStatus(@PathVariable String id,
                                               @jakarta.validation.Valid @RequestBody com.kandypack.kandypackbackend.dto.OrderStatusUpdateRequest request) {

        java.util.List<String> validStatuses = java.util.List.of("placed", "scheduled", "dispatched", "delivered", "cancelled");
        if (!validStatuses.contains(request.getStatus())) {
            return ResponseEntity.badRequest().body("Invalid status. Must be one of: " + validStatuses);
        }

        return ResponseEntity.ok(orderAssignmentService.toResponse(
                orderAssignmentService.updateStatus(id, request.getStatus())));
    }

    @Autowired
    private CustomerOrderRepository orderRepository;

    @Autowired
    private OrderAssignmentService orderAssignmentService;

    @GetMapping
    @org.springframework.security.access.prepost.PreAuthorize("hasAnyRole('ADMIN', 'DISPATCHER', 'STORE_MANAGER', 'DRIVER')")
    public List<OrderResponse> getAllOrders() {
        return orderRepository.findAll().stream()
                .map(orderAssignmentService::toResponse)
                .collect(Collectors.toList());
    }
    @GetMapping("/export/csv")
    @org.springframework.security.access.prepost.PreAuthorize("hasAnyRole('ADMIN', 'DISPATCHER')")
    public ResponseEntity<String> exportOrdersCsv() {
        List<CustomerOrder> allOrders = orderRepository.findAll();

        StringBuilder csv = new StringBuilder();
        csv.append("Order ID,Customer,Amount,Placement Date,Delivery Date,Status\n");

        for (CustomerOrder o : allOrders) {
            csv.append(o.getOrderId()).append(",")
                    .append(o.getCustomer().getCustomerName()).append(",")
                    .append(o.getAmount()).append(",")
                    .append(o.getPlacementDate()).append(",")
                    .append(o.getDeliveryDate()).append(",")
                    .append(o.getStatus()).append("\n");
        }

        org.springframework.http.HttpHeaders headers = new org.springframework.http.HttpHeaders();
        headers.add("Content-Disposition", "attachment; filename=orders_report.csv");
        headers.add("Content-Type", "text/csv");

        return ResponseEntity.ok()
                .headers(headers)
                .body(csv.toString());
    }
    @GetMapping("/my")
    @org.springframework.security.access.prepost.PreAuthorize("hasRole('CUSTOMER')")
    public List<OrderResponse> getMyOrders(@org.springframework.security.core.annotation.AuthenticationPrincipal String customerId) {
        return orderRepository.findAll().stream()
                .filter(o -> o.getCustomer().getCustomerId().equals(customerId))
                .map(orderAssignmentService::toResponse)
                .collect(Collectors.toList());
    }


    @GetMapping("/{id}")
    @org.springframework.security.access.prepost.PreAuthorize("isAuthenticated()")
    public ResponseEntity<OrderResponse> getOrderById(@PathVariable String id,
            org.springframework.security.core.Authentication authentication) {
        return orderRepository.findById(id).map(order -> {
            boolean staff = authentication.getAuthorities().stream().anyMatch(a ->
                java.util.Set.of("ROLE_ADMIN", "ROLE_DISPATCHER", "ROLE_STORE_MANAGER", "ROLE_DRIVER").contains(a.getAuthority()));
            if (!staff && !order.getCustomer().getCustomerId().equals(authentication.getName())) {
                throw new org.springframework.security.access.AccessDeniedException("This is not your order");
            }
            return ResponseEntity.ok(orderAssignmentService.toResponse(order));
        }).orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    @org.springframework.security.access.prepost.PreAuthorize("hasRole('CUSTOMER')")
    public ResponseEntity<OrderResponse> createOrder(@Valid @RequestBody OrderRequest request,
            @org.springframework.security.core.annotation.AuthenticationPrincipal String customerId) {
        request.setCustomerId(customerId);
        CustomerOrder created = orderAssignmentService.placeOrder(request);
        return ResponseEntity.ok(orderAssignmentService.toResponse(created));
    }

}

interface CustomerOrderRepository extends JpaRepository<CustomerOrder, String> {
}