package com.kandypack.kandypackbackend.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;

@Entity
@Table(name = "train")
public class Train {

    @Id
    @Column(name = "train_id")
    private String trainId;

    @Column(name = "size", nullable = false)
    private BigDecimal size;

    @Column(name = "capacity_per_product", nullable = false)
    private BigDecimal capacityPerProduct;

    public String getTrainId() { return trainId; }
    public void setTrainId(String trainId) { this.trainId = trainId; }

    public BigDecimal getSize() { return size; }
    public void setSize(BigDecimal size) { this.size = size; }

    public BigDecimal getCapacityPerProduct() { return capacityPerProduct; }
    public void setCapacityPerProduct(BigDecimal capacityPerProduct) { this.capacityPerProduct = capacityPerProduct; }
}