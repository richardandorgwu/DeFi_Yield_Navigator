import { describe, expect, it } from "vitest";

// Mock the Clarity VM and contract functions
class MockClarityVM {
  private contractOwner: string = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM";
  private strategies: Map<number, any> = new Map();
  private users: Map<string, any> = new Map();
  private userAllocations: Map<string, Map<number, number>> = new Map();
  private strategyCount: number = 0;
  private totalFundsLocked: number = 0;
  private assetContract: string = "SP000000000000000000002Q6VF78.dummy-token";
  private paused: boolean = false;

  // Risk profiles
  private readonly RISK_CONSERVATIVE = 1;
  private readonly RISK_MODERATE = 2;
  private readonly RISK_AGGRESSIVE = 3;

  // Error codes
  private readonly ERR_OWNER_ONLY = 100;
  private readonly ERR_INVALID_STRATEGY = 101;
  private readonly ERR_STRATEGY_EXISTS = 102;
  private readonly ERR_INSUFFICIENT_BALANCE = 103;
  private readonly ERR_INVALID_AMOUNT = 104;
  private readonly ERR_INVALID_RISK_PROFILE = 105;
  private readonly ERR_INVALID_ALLOCATION = 106;
  private readonly ERR_INVALID_PROTOCOL = 107;
  private readonly ERR_STRATEGY_INACTIVE = 108;
  private readonly ERR_UNAUTHORIZED = 109;
  private readonly ERR_INVALID_RISK_SCORE = 110;
  private readonly ERR_GENERAL = 999;

  constructor() {}

  // Public functions that simulate contract functions
  public addStrategy(caller: string, protocol: string, currentApy: number, riskScore: number): { type: string; value: any } {
    if (caller !== this.contractOwner) {
      return { type: "err", value: this.ERR_OWNER_ONLY };
    }

    if (protocol === "SP000000000000000000002Q6VF78") {
      return { type: "err", value: this.ERR_INVALID_PROTOCOL };
    }

    if (riskScore > 100) {
      return { type: "err", value: this.ERR_INVALID_RISK_SCORE };
    }

    const strategyId = this.strategyCount;
    this.strategies.set(strategyId, {
      protocol,
      currentApy,
      riskScore,
      active: true,
      allocatedFunds: 0
    });

    this.strategyCount++;
    return { type: "ok", value: strategyId };
  }

  public updateStrategyApy(caller: string, strategyId: number, newApy: number): { type: string; value: any } {
    if (caller !== this.contractOwner) {
      return { type: "err", value: this.ERR_OWNER_ONLY };
    }

    if (!this.strategies.has(strategyId)) {
      return { type: "err", value: this.ERR_INVALID_STRATEGY };
    }

    const strategy = this.strategies.get(strategyId);
    strategy.currentApy = newApy;
    this.strategies.set(strategyId, strategy);

    return { type: "ok", value: true };
  }

  public setStrategyActive(caller: string, strategyId: number, active: boolean): { type: string; value: any } {
    if (caller !== this.contractOwner) {
      return { type: "err", value: this.ERR_OWNER_ONLY };
    }

    if (!this.strategies.has(strategyId)) {
      return { type: "err", value: this.ERR_INVALID_STRATEGY };
    }

    const strategy = this.strategies.get(strategyId);
    strategy.active = active;
    this.strategies.set(strategyId, strategy);

    return { type: "ok", value: true };
  }

  public deposit(caller: string, tokenContract: string, amount: number): { type: string; value: any } {
    if (tokenContract !== this.assetContract) {
      return { type: "err", value: this.ERR_INVALID_PROTOCOL };
    }

    if (amount <= 0) {
      return { type: "err", value: this.ERR_INVALID_AMOUNT };
    }

    // Get user data or create default
    const userData = this.users.get(caller) || { 
      riskProfile: this.RISK_MODERATE, 
      totalDeposited: 0 
    };

    // Update user's total deposited
    userData.totalDeposited += amount;
    this.users.set(caller, userData);

    // Update total funds locked
    this.totalFundsLocked += amount;

    // Handle allocation
    this.handleDepositAllocation(caller);

    return { type: "ok", value: true };
  }

  public withdraw(caller: string, tokenContract: string, amount: number): { type: string; value: any } {
    if (tokenContract !== this.assetContract) {
      return { type: "err", value: this.ERR_INVALID_PROTOCOL };
    }

    if (amount <= 0) {
      return { type: "err", value: this.ERR_INVALID_AMOUNT };
    }

    // Get user data or create default
    const userData = this.users.get(caller) || { 
      riskProfile: this.RISK_MODERATE, 
      totalDeposited: 0 
    };

    if (userData.totalDeposited < amount) {
      return { type: "err", value: this.ERR_INSUFFICIENT_BALANCE };
    }

    // Update user's total deposited
    userData.totalDeposited -= amount;
    this.users.set(caller, userData);

    // Update total funds locked
    this.totalFundsLocked -= amount;

    return { type: "ok", value: true };
  }

  public setRiskProfile(caller: string, profile: number): { type: string; value: any } {
    if (profile !== this.RISK_CONSERVATIVE && 
        profile !== this.RISK_MODERATE && 
        profile !== this.RISK_AGGRESSIVE) {
      return { type: "err", value: this.ERR_INVALID_RISK_PROFILE };
    }

    // Get user data or create default
    const userData = this.users.get(caller) || { 
      riskProfile: this.RISK_MODERATE, 
      totalDeposited: 0 
    };

    // Update user's risk profile
    userData.riskProfile = profile;
    this.users.set(caller, userData);

    // Only reallocate if the user has funds deposited
    if (userData.totalDeposited > 0) {
      this.rebalanceAfterProfileChange(caller);
    }

    return { type: "ok", value: true };
  }

  public reallocateFunds(caller: string, strategyIds: number[], allocations: number[]): { type: string; value: any } {
    // Get user data or create default
    const userData = this.users.get(caller) || { 
      riskProfile: this.RISK_MODERATE, 
      totalDeposited: 0 
    };

    if (userData.totalDeposited <= 0) {
      return { type: "err", value: this.ERR_INSUFFICIENT_BALANCE };
    }

    if (strategyIds.length !== allocations.length) {
      return { type: "err", value: this.ERR_INVALID_ALLOCATION };
    }

    // Check total allocations sum to 10000
    const sum = allocations.reduce((a, b) => a + b, 0);
    if (sum !== 10000) {
      return { type: "err", value: this.ERR_INVALID_ALLOCATION };
    }

    // Validate all strategies exist and are active
    for (const strategyId of strategyIds) {
      if (!this.strategies.has(strategyId)) {
        return { type: "err", value: this.ERR_INVALID_STRATEGY };
      }
      
      const strategy = this.strategies.get(strategyId);
      if (!strategy.active) {
        return { type: "err", value: this.ERR_STRATEGY_INACTIVE };
      }
    }

    // Update allocations
    this.updateUserAllocations(caller, strategyIds, allocations);

    return { type: "ok", value: true };
  }

  public setPaused(caller: string, newPaused: boolean): { type: string; value: any } {
    if (caller !== this.contractOwner) {
      return { type: "err", value: this.ERR_OWNER_ONLY };
    }

    this.paused = newPaused;
    return { type: "ok", value: true };
  }

  public isPaused(): boolean {
    return this.paused;
  }

  // Read-only functions
  public getStrategy(strategyId: number): any {
    return this.strategies.get(strategyId);
  }

  public getUserRiskProfile(user: string): number {
    const userData = this.users.get(user);
    return userData ? userData.riskProfile : this.RISK_MODERATE;
  }

  public getUserTotalValue(user: string): number {
    const userData = this.users.get(user);
    return userData ? userData.totalDeposited : 0;
  }

  public getUserAllocation(user: string, strategyId: number): number {
    const userAllocationMap = this.userAllocations.get(user);
    if (!userAllocationMap) return 0;
    return userAllocationMap.get(strategyId) || 0;
  }

  public getTotalFundsLocked(): number {
    return this.totalFundsLocked;
  }

  public getStrategyCount(): number {
    return this.strategyCount;
  }

  // Private helper functions
  private handleDepositAllocation(user: string): void {
    this.allocateFunds(user);
  }

  private rebalanceAfterProfileChange(user: string): void {
    this.allocateFunds(user);
  }

  private allocateFunds(user: string): void {
    const allocationData = this.getOptimalAllocations(user);
    this.updateUserAllocations(user, allocationData.strategyIds, allocationData.percentages);
  }

  private updateUserAllocations(user: string, strategyIds: number[], allocations: number[]): void {
    // Clear existing allocations
    if (!this.userAllocations.has(user)) {
      this.userAllocations.set(user, new Map());
    } else {
      this.userAllocations.get(user)?.clear();
    }

    // Set new allocations
    const userAllocationMap = this.userAllocations.get(user)!;
    for (let i = 0; i < strategyIds.length; i++) {
      userAllocationMap.set(strategyIds[i], allocations[i]);
    }
  }

  private getOptimalAllocations(user: string): { strategyIds: number[], percentages: number[] } {
    const userData = this.users.get(user);
    const userProfile = userData ? userData.riskProfile : this.RISK_MODERATE;

    // Simplified allocation based on risk profile
    // In production, this would use more sophisticated logic
    if (userProfile === this.RISK_CONSERVATIVE) {
      return { strategyIds: [0, 1], percentages: [7000, 3000] };
    } else if (userProfile === this.RISK_MODERATE) {
      return { strategyIds: [0, 1], percentages: [5000, 5000] };
    } else { // RISK_AGGRESSIVE
      return { strategyIds: [0, 1], percentages: [3000, 7000] };
    }
  }
}

describe("Yield Optimizer Contract", () => {
  // Setup
  let vm: MockClarityVM;
  const owner = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM";
  const user1 = "ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG";
  const user2 = "ST2JHG361ZXG51QTKY2NQCVBPPRRE2KZB1HR05NNC";
  const dummyToken = "SP000000000000000000002Q6VF78.dummy-token";
  const protocol1 = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.protocol1";
  const protocol2 = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.protocol2";

  beforeEach(() => {
    vm = new MockClarityVM();
  });

  describe("Strategy Management", () => {
    it("should add a new strategy", () => {
      const result = vm.addStrategy(owner, protocol1, 500, 30);
      expect(result.type).toBe("ok");
      expect(result.value).toBe(0);

      const strategy = vm.getStrategy(0);
      expect(strategy).toBeDefined();
      expect(strategy.protocol).toBe(protocol1);
      expect(strategy.currentApy).toBe(500);
      expect(strategy.riskScore).toBe(30);
      expect(strategy.active).toBe(true);
    });

    it("should not allow non-owner to add a strategy", () => {
      const result = vm.addStrategy(user1, protocol1, 500, 30);
      expect(result.type).toBe("err");
      expect(result.value).toBe(100); // ERR_OWNER_ONLY
    });

    it("should update strategy APY", () => {
      vm.addStrategy(owner, protocol1, 500, 30);
      const result = vm.updateStrategyApy(owner, 0, 600);
      expect(result.type).toBe("ok");

      const strategy = vm.getStrategy(0);
      expect(strategy.currentApy).toBe(600);
    });

    it("should set strategy active status", () => {
      vm.addStrategy(owner, protocol1, 500, 30);
      const result = vm.setStrategyActive(owner, 0, false);
      expect(result.type).toBe("ok");

      const strategy = vm.getStrategy(0);
      expect(strategy.active).toBe(false);
    });
  });

  describe("User Deposits and Withdrawals", () => {
    it("should allow user to deposit funds", () => {
      // Add strategies first
      vm.addStrategy(owner, protocol1, 500, 30);
      vm.addStrategy(owner, protocol2, 800, 70);

      const result = vm.deposit(user1, dummyToken, 1000);
      expect(result.type).toBe("ok");
      expect(vm.getUserTotalValue(user1)).toBe(1000);
      expect(vm.getTotalFundsLocked()).toBe(1000);
    });

    it("should not allow deposit with invalid amount", () => {
      const result = vm.deposit(user1, dummyToken, 0);
      expect(result.type).toBe("err");
      expect(result.value).toBe(104); // ERR_INVALID_AMOUNT
    });

    it("should allow user to withdraw funds", () => {
      // Add strategies first
      vm.addStrategy(owner, protocol1, 500, 30);
      vm.addStrategy(owner, protocol2, 800, 70);

      // Deposit first
      vm.deposit(user1, dummyToken, 1000);

      const result = vm.withdraw(user1, dummyToken, 500);
      expect(result.type).toBe("ok");
      expect(vm.getUserTotalValue(user1)).toBe(500);
      expect(vm.getTotalFundsLocked()).toBe(500);
    });

    it("should not allow withdrawal with insufficient balance", () => {
      vm.deposit(user1, dummyToken, 1000);
      const result = vm.withdraw(user1, dummyToken, 1500);
      expect(result.type).toBe("err");
      expect(result.value).toBe(103); // ERR_INSUFFICIENT_BALANCE
    });
  });

  describe("Risk Profiles and Allocations", () => {
    it("should set user risk profile", () => {
      const result = vm.setRiskProfile(user1, 1); // RISK_CONSERVATIVE
      expect(result.type).toBe("ok");
      expect(vm.getUserRiskProfile(user1)).toBe(1);
    });

    it("should not allow invalid risk profile", () => {
      const result = vm.setRiskProfile(user1, 4); // Invalid
      expect(result.type).toBe("err");
      expect(result.value).toBe(105); // ERR_INVALID_RISK_PROFILE
    });

    it("should allow manual reallocation of funds", () => {
      // Add strategies first
      vm.addStrategy(owner, protocol1, 500, 30);
      vm.addStrategy(owner, protocol2, 800, 70);

      // Deposit funds
      vm.deposit(user1, dummyToken, 1000);

      const result = vm.reallocateFunds(user1, [0, 1], [3000, 7000]);
      expect(result.type).toBe("ok");
      expect(vm.getUserAllocation(user1, 0)).toBe(3000);
      expect(vm.getUserAllocation(user1, 1)).toBe(7000);
    });

    it("should not allow reallocation with invalid allocation sum", () => {
      // Add strategies first
      vm.addStrategy(owner, protocol1, 500, 30);
      vm.addStrategy(owner, protocol2, 800, 70);

      // Deposit funds
      vm.deposit(user1, dummyToken, 1000);

      const result = vm.reallocateFunds(user1, [0, 1], [3000, 6000]); // Sum is 9000, not 10000
      expect(result.type).toBe("err");
      expect(result.value).toBe(106); // ERR_INVALID_ALLOCATION
    });
  });

  describe("Emergency Controls", () => {
    it("should allow owner to pause the contract", () => {
      const result = vm.setPaused(owner, true);
      expect(result.type).toBe("ok");
      expect(vm.isPaused()).toBe(true);
    });

    it("should not allow non-owner to pause the contract", () => {
      const result = vm.setPaused(user1, true);
      expect(result.type).toBe("err");
      expect(result.value).toBe(100); // ERR_OWNER_ONLY
    });
  });
});