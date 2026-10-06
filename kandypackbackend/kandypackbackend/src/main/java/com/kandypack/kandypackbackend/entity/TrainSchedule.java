package com.kandypack.kandypackbackend.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "train_schedule")
public class TrainSchedule {

    @Id
    @Column(name = "trip_id")
    private String tripId;

    @ManyToOne
    @JoinColumn(name = "city_id", nullable = false)
    private City city;

    @Column(name = "departure_datetime", nullable = false)
    private LocalDateTime departureDatetime;

    @Column(name = "arrival_datetime", nullable = false)
    private LocalDateTime arrivalDatetime;

    @ManyToOne
    @JoinColumn(name = "train_id", nullable = false)
    private Train train;

    @ManyToOne
    @JoinColumn(name = "store_id", nullable = false)
    private Store store;

    @Column(name = "available_capacity", nullable = false)
    private BigDecimal availableCapacity;

    public String getTripId() { return tripId; }
    public void setTripId(String tripId) { this.tripId = tripId; }

    public City getCity() { return city; }
    public void setCity(City city) { this.city = city; }

    public LocalDateTime getDepartureDatetime() { return departureDatetime; }
    public void setDepartureDatetime(LocalDateTime departureDatetime) { this.departureDatetime = departureDatetime; }

    public LocalDateTime getArrivalDatetime() { return arrivalDatetime; }
    public void setArrivalDatetime(LocalDateTime arrivalDatetime) { this.arrivalDatetime = arrivalDatetime; }

    public Train getTrain() { return train; }
    public void setTrain(Train train) { this.train = train; }

    public Store getStore() { return store; }
    public void setStore(Store store) { this.store = store; }

    public BigDecimal getAvailableCapacity() { return availableCapacity; }
    public void setAvailableCapacity(BigDecimal availableCapacity) { this.availableCapacity = availableCapacity; }
}