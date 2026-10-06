package com.kandypack.kandypackbackend.service;

import com.kandypack.kandypackbackend.dto.OrderRequest;
import com.kandypack.kandypackbackend.dto.OrderResponse;
import com.kandypack.kandypackbackend.entity.*;
import com.kandypack.kandypackbackend.repository.*;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;

@Service
public class OrderAssignmentService {
    @Autowired private CustomerRepo customerRepo;
    @Autowired private ProductRepo productRepo;
    @Autowired private RouteRepository routeRepository;
    @Autowired private OrderRepo orderRepo;
    @Autowired private OrderItemRepo orderItemRepo;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private EntityManager entityManager;

    @Transactional
    public CustomerOrder placeOrder(OrderRequest request) {
        LocalDate placementDate = LocalDate.now(ZoneId.of("Asia/Colombo"));
        if (request.getDeliveryDate().isBefore(placementDate.plusDays(7))) {
            throw new IllegalArgumentException("Delivery date must be at least 7 days after placement date");
        }
        Customer customer = customerRepo.findById(request.getCustomerId())
                .orElseThrow(() -> new IllegalArgumentException("Customer not found"));
        Route route = routeRepository.findById(request.getRouteId())
                .orElseThrow(() -> new IllegalArgumentException("Route not found"));
        if (!route.getStore().getCity().getCityId().equals(customer.getCity().getCityId())) {
            throw new IllegalArgumentException("Select a route in your delivery city");
        }

        // Consolidate duplicate products before saving the composite-key order_item rows.
        Map<String, Integer> quantities = new TreeMap<>();
        for (OrderRequest.OrderItemRequest item : request.getItems()) {
            try {
                quantities.merge(item.getProductId(), item.getQuantity(), Math::addExact);
            } catch (ArithmeticException ex) {
                throw new IllegalArgumentException("Total quantity is too large");
            }
        }
        Map<String, Product> products = new TreeMap<>();
        BigDecimal total = BigDecimal.ZERO;
        for (Map.Entry<String, Integer> entry : quantities.entrySet()) {
            Product product = productRepo.findById(entry.getKey())
                    .orElseThrow(() -> new IllegalArgumentException("Product not found: " + entry.getKey()));
            products.put(entry.getKey(), product);
            total = total.add(product.getPrice().multiply(BigDecimal.valueOf(entry.getValue())));
        }

        CustomerOrder order = new CustomerOrder();
        order.setOrderId("ORD" + UUID.randomUUID().toString().substring(0, 7).toUpperCase());
        order.setCustomer(customer);
        order.setAmount(total);
        order.setPlacementDate(placementDate);
        order.setDeliveryDate(request.getDeliveryDate());
        order.setStatus("placed");
        order = orderRepo.saveAndFlush(order);
        for (Map.Entry<String, Integer> entry : quantities.entrySet()) {
            Product product = products.get(entry.getKey());
            OrderItem item = new OrderItem();
            item.setId(new OrderItemId(order.getOrderId(), product.getProductId()));
            item.setOrder(order);
            item.setProduct(product);
            item.setQuantity(entry.getValue());
            item.setPrice(product.getPrice());
            orderItemRepo.save(item);
        }
        entityManager.flush();

        // One transaction covers order + items + all allocations. PostgreSQL owns capacity.
        jdbc.update("CALL public.assign_order_to_trips(CAST(? AS varchar), CAST(? AS varchar), CAST(? AS varchar))",
                order.getOrderId(), route.getRouteId(), request.getTripId());
        entityManager.refresh(order); // Procedure changed placed -> scheduled.
        return order;
    }

    @Transactional
    public CustomerOrder updateStatus(String orderId, String status) {
        CustomerOrder order = entityManager.find(CustomerOrder.class, orderId, LockModeType.PESSIMISTIC_WRITE);
        if (order == null) throw new IllegalArgumentException("Order not found");
        order.setStatus(status);
        entityManager.flush(); // Database validates transition and releases eligible cancellations.
        return order;
    }

    @Transactional(readOnly = true)
    public OrderResponse toResponse(CustomerOrder order) {
        OrderResponse response = new OrderResponse(order);
        response.setAllocations(jdbc.query("""
            SELECT a.trip_id, a.product_id, p.product_name, a.quantity,
                   a.quantity * a.space_per_unit AS reserved_space, ot.route_id,
                   ts.departure_datetime, ts.arrival_datetime, a.reservation_active
            FROM public.order_trip_item a
            JOIN public.product p USING (product_id)
            JOIN public.order_travel ot ON ot.order_id = a.order_id AND ot.trip_id = a.trip_id
            JOIN public.train_schedule ts ON ts.trip_id = a.trip_id
            WHERE a.order_id = ? ORDER BY ts.departure_datetime, a.trip_id, a.product_id
            """, (rs, row) -> new OrderResponse.TrainAllocation(
                rs.getString("trip_id"), rs.getString("product_id"), rs.getString("product_name"),
                rs.getInt("quantity"), rs.getBigDecimal("reserved_space"), rs.getString("route_id"),
                rs.getTimestamp("departure_datetime").toLocalDateTime(),
                rs.getTimestamp("arrival_datetime").toLocalDateTime(), rs.getBoolean("reservation_active")),
                order.getOrderId()));
        return response;
    }
}
