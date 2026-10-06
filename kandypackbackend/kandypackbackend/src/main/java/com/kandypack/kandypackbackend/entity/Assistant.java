package com.kandypack.kandypackbackend.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;

@Entity
@Table(name = "assistant")
public class Assistant {

    @Id
    @Column(name = "assistant_id")
    private String assistantId;

    @Column(name = "assistant_name", nullable = false)
    private String assistantName;

    @Column(name = "weekly_hours_logged", nullable = false)
    private BigDecimal weeklyHoursLogged;

    public String getAssistantId() { return assistantId; }
    public void setAssistantId(String assistantId) { this.assistantId = assistantId; }

    public String getAssistantName() { return assistantName; }
    public void setAssistantName(String assistantName) { this.assistantName = assistantName; }

    public BigDecimal getWeeklyHoursLogged() { return weeklyHoursLogged; }
    public void setWeeklyHoursLogged(BigDecimal weeklyHoursLogged) { this.weeklyHoursLogged = weeklyHoursLogged; }
}