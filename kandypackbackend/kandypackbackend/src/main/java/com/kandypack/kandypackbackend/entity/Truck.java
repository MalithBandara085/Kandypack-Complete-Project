package com.kandypack.kandypackbackend.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;

@Entity
@Table(name = "truck")
public class Truck {

    @Id
    @Column(name = "truck_id")
    private String truckId;

    @ManyToOne
    @JoinColumn(name = "store_id", nullable = false)
    private Store store;

    @Column(name = "plate_number", nullable = false)
    private String plateNumber;

    @Column(name = "capacity", nullable = false)
    private BigDecimal capacity;

    public String getTruckId() { return truckId; }
    public void setTruckId(String truckId) { this.truckId = truckId; }

    public Store getStore() { return store; }
    public void setStore(Store store) { this.store = store; }

    public String getPlateNumber() { return plateNumber; }
    public void setPlateNumber(String plateNumber) { this.plateNumber = plateNumber; }

    public BigDecimal getCapacity() { return capacity; }
    public void setCapacity(BigDecimal capacity) { this.capacity = capacity; }
}