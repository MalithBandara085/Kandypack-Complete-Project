package com.kandypack.kandypackbackend.dto;

import com.kandypack.kandypackbackend.entity.Customer;

public class CustomerResponse {

    private String customerId;
    private String customerName;
    private String deliveryAddress;
    private String phoneNumber;
    private String email;
    private String cityName;

    public CustomerResponse(Customer customer) {
        this.customerId = customer.getCustomerId();
        this.customerName = customer.getCustomerName();
        this.deliveryAddress = customer.getDeliveryAddress();
        this.phoneNumber = customer.getPhoneNumber();
        this.email = customer.getEmail();
        this.cityName = customer.getCity().getCityName();
    }

    public String getCustomerId() { return customerId; }
    public String getCustomerName() { return customerName; }
    public String getDeliveryAddress() { return deliveryAddress; }
    public String getPhoneNumber() { return phoneNumber; }
    public String getEmail() { return email; }
    public String getCityName() { return cityName; }
}