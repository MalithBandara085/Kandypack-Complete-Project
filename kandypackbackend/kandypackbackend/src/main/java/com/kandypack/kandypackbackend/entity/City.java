package com.kandypack.kandypackbackend.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "city")
public class City {

    @Id
    @Column(name = "city_id")
    private String cityId;

    @Column(name = "city_name", nullable = false)
    private String cityName;

    @Column(name = "has_rail_station", nullable = false)
    private Boolean hasRailStation;

    public String getCityId() { return cityId; }
    public void setCityId(String cityId) { this.cityId = cityId; }

    public String getCityName() { return cityName; }
    public void setCityName(String cityName) { this.cityName = cityName; }

    public Boolean getHasRailStation() { return hasRailStation; }
    public void setHasRailStation(Boolean hasRailStation) { this.hasRailStation = hasRailStation; }
}