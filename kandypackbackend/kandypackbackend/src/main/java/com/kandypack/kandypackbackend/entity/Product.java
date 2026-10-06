package com.kandypack.kandypackbackend.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;

@Entity
@Table(name = "product")
public class Product {

    @Id
    @Column(name = "product_id")
    private String productId;

    @Column(name = "product_name", nullable = false)
    private String productName;

    @Column(name = "space_consumption", nullable = false)
    private BigDecimal spaceConsumption;

    @Column(name = "price", nullable = false)
    private BigDecimal price;

    public String getProductId() { return productId; }
    public void setProductId(String productId) { this.productId = productId; }

    public String getProductName() { return productName; }
    public void setProductName(String productName) { this.productName = productName; }

    public BigDecimal getSpaceConsumption() { return spaceConsumption; }
    public void setSpaceConsumption(BigDecimal spaceConsumption) { this.spaceConsumption = spaceConsumption; }

    public BigDecimal getPrice() { return price; }
    public void setPrice(BigDecimal price) { this.price = price; }
}