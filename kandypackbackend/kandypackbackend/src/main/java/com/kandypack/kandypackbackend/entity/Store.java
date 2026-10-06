package com.kandypack.kandypackbackend.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "store")
public class Store {

    @Id
    @Column(name = "store_id")
    private String storeId;

    @ManyToOne
    @JoinColumn(name = "city_id", nullable = false)
    private City city;

    public String getStoreId() { return storeId; }
    public void setStoreId(String storeId) { this.storeId = storeId; }

    public City getCity() { return city; }
    public void setCity(City city) { this.city = city; }
}