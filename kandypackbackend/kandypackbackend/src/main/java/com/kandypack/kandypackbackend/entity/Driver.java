package com.kandypack.kandypackbackend.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;

@Entity
@Table(name = "driver")
public class Driver {

    @Id
    @Column(name = "driver_id")
    private String driverId;

    @Column(name = "driver_name", nullable = false)
    private String driverName;

    @Column(name = "weekly_hours_logged", nullable = false)
    private BigDecimal weeklyHoursLogged;

    public String getDriverId() { return driverId; }
    public void setDriverId(String driverId) { this.driverId = driverId; }

    public String getDriverName() { return driverName; }
    public void setDriverName(String driverName) { this.driverName = driverName; }

    public BigDecimal getWeeklyHoursLogged() { return weeklyHoursLogged; }
    public void setWeeklyHoursLogged(BigDecimal weeklyHoursLogged) { this.weeklyHoursLogged = weeklyHoursLogged; }
}