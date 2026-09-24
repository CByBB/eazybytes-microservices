package com.eazybytes.accounts.dto;

public class AccountsMsgDto {

    private Long accountNumber;
    private String name;
    private String email;
    private String mobileNumber;

    public AccountsMsgDto() {
    }

    public AccountsMsgDto(Long accountNumber, String name, String email, String mobileNumber) {
        this.accountNumber = accountNumber;
        this.name = name;
        this.email = email;
        this.mobileNumber = mobileNumber;
    }

    public Long getAccountNumber() {
        return accountNumber;
    }

    public void setAccountNumber(Long accountNumber) {
        this.accountNumber = accountNumber;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getMobileNumber() {
        return mobileNumber;
    }

    public void setMobileNumber(String mobileNumber) {
        this.mobileNumber = mobileNumber;
    }
}
