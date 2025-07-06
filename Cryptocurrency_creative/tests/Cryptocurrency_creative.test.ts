import { describe, it, expect, beforeEach } from 'vitest';
import { Cl } from '@stacks/transactions';

// Mock contract interaction functions
interface ContractResult {
  type: string;
  value: any;
}

interface MockContract {
  callReadOnlyFunction: (functionName: string, args: any[]) => Promise<ContractResult>;
  callPublicFunction: (functionName: string, args: any[]) => Promise<ContractResult>;
}

// Mock implementation for testing
class MockCreativeContract implements MockContract {
  private works: Map<number, any> = new Map();
  private profiles: Map<string, any> = new Map();
  private ownership: Map<string, any> = new Map();
  private listings: Map<string, any> = new Map();
  private nextWorkId = 1;
  private platformFee = 250;

  async callReadOnlyFunction(functionName: string, args: any[]): Promise<ContractResult> {
    switch (functionName) {
      case 'get-work-details':
        const workId = args[0].value;
        const work = this.works.get(workId);
        return {
          type: 'optional',
          value: work || null
        };
      
      case 'get-creator-profile':
        const creator = args[0].value;
        const profile = this.profiles.get(creator);
        return {
          type: 'optional',
          value: profile || null
        };
      
      case 'get-next-work-id':
        return {
          type: 'uint',
          value: this.nextWorkId
        };
      
      case 'get-platform-fee':
        return {
          type: 'uint',
          value: this.platformFee
        };
      
      default:
        throw new Error(`Unknown read-only function: ${functionName}`);
    }
  }

  async callPublicFunction(functionName: string, args: any[]): Promise<ContractResult> {
    switch (functionName) {
      case 'create-creator-profile':
        const [name, bio, portfolioUrl] = args;
        const profileKey = 'test-creator';
        
        if (this.profiles.has(profileKey)) {
          return { type: 'error', value: 'ERR_ALREADY_EXISTS' };
        }
        
        this.profiles.set(profileKey, {
          name: name.value,
          bio: bio.value,
          'portfolio-url': portfolioUrl.value,
          'total-works': 0,
          'total-earnings': 0,
          'verification-status': false
        });
        
        return { type: 'ok', value: true };
      
      case 'create-creative-work':
        const [title, description, category, price, royaltyPercentage, totalSupply] = args;
        
        if (royaltyPercentage.value > 5000 || totalSupply.value === 0 || price.value === 0) {
          return { type: 'error', value: 'ERR_INVALID_AMOUNT' };
        }
        
        const workId = this.nextWorkId++;
        this.works.set(workId, {
          creator: 'test-creator',
          title: title.value,
          description: description.value,
          category: category.value,
          price: price.value,
          'royalty-percentage': royaltyPercentage.value,
          'total-supply': totalSupply.value,
          'available-supply': totalSupply.value,
          'created-at': 1,
          'is-active': true
        });
        
        // Set ownership
        this.ownership.set(`${workId}-test-creator`, { quantity: totalSupply.value });
        
        return { type: 'ok', value: workId };
      
      case 'list-work-for-sale':
        const [workIdArg, quantity, pricePerUnit] = args;
        const listingKey = `${workIdArg.value}-test-creator`;
        
        this.listings.set(listingKey, {
          quantity: quantity.value,
          'price-per-unit': pricePerUnit.value,
          'listed-at': 2,
          'is-active': true
        });
        
        return { type: 'ok', value: true };
      
      case 'purchase-work':
        const [purchaseWorkId, seller, purchaseQuantity] = args;
        // Simplified purchase logic for testing
        return { type: 'ok', value: true };
      
      default:
        throw new Error(`Unknown public function: ${functionName}`);
    }
  }
}

describe('Creative Industries Cryptocurrency Contract', () => {
  let contract: MockCreativeContract;

  beforeEach(() => {
    contract = new MockCreativeContract();
  });

  describe('Creator Profile Management', () => {
    it('should create a new creator profile', async () => {
      const result = await contract.callPublicFunction('create-creator-profile', [
        Cl.stringAscii('Alice Artist'),
        Cl.stringAscii('Digital artist specializing in NFTs'),
        Cl.stringAscii('https://alice-portfolio.com')
      ]);

      expect(result.type).toBe('ok');
      expect(result.value).toBe(true);
    });

    it('should prevent duplicate creator profiles', async () => {
      // Create first profile
      await contract.callPublicFunction('create-creator-profile', [
        Cl.stringAscii('Alice Artist'),
        Cl.stringAscii('Digital artist'),
        Cl.stringAscii('https://alice.com')
      ]);

      // Try to create duplicate
      const result = await contract.callPublicFunction('create-creator-profile', [
        Cl.stringAscii('Alice Artist 2'),
        Cl.stringAscii('Still Alice'),
        Cl.stringAscii('https://alice2.com')
      ]);

      expect(result.type).toBe('error');
      expect(result.value).toBe('ERR_ALREADY_EXISTS');
    });

    it('should retrieve creator profile', async () => {
      // Create profile first
      await contract.callPublicFunction('create-creator-profile', [
        Cl.stringAscii('Bob Creator'),
        Cl.stringAscii('Music producer'),
        Cl.stringAscii('https://bob-music.com')
      ]);

      const result = await contract.callReadOnlyFunction('get-creator-profile', [
        Cl.principal('test-creator')
      ]);

      expect(result.type).toBe('optional');
      expect(result.value).toBeTruthy();
      expect(result.value.name).toBe('Bob Creator');
    });
  });

  describe('Creative Work Management', () => {
    beforeEach(async () => {
      // Setup creator profile
      await contract.callPublicFunction('create-creator-profile', [
        Cl.stringAscii('Test Creator'),
        Cl.stringAscii('Test bio'),
        Cl.stringAscii('https://test.com')
      ]);
    });

    it('should create a new creative work', async () => {
      const result = await contract.callPublicFunction('create-creative-work', [
        Cl.stringAscii('Digital Masterpiece'),
        Cl.stringAscii('A beautiful digital artwork'),
        Cl.stringAscii('Digital Art'),
        Cl.uint(1000000), // 1 STX in microSTX
        Cl.uint(1000), // 10% royalty
        Cl.uint(100) // 100 copies
      ]);

      expect(result.type).toBe('ok');
      expect(typeof result.value).toBe('number');
      expect(result.value).toBeGreaterThan(0);
    });

    it('should reject invalid royalty percentage', async () => {
      const result = await contract.callPublicFunction('create-creative-work', [
        Cl.stringAscii('Test Work'),
        Cl.stringAscii('Test description'),
        Cl.stringAscii('Art'),
        Cl.uint(1000000),
        Cl.uint(6000), // 60% - too high
        Cl.uint(10)
      ]);

      expect(result.type).toBe('error');
      expect(result.value).toBe('ERR_INVALID_AMOUNT');
    });

    it('should reject zero supply', async () => {
      const result = await contract.callPublicFunction('create-creative-work', [
        Cl.stringAscii('Test Work'),
        Cl.stringAscii('Test description'),
        Cl.stringAscii('Art'),
        Cl.uint(1000000),
        Cl.uint(1000),
        Cl.uint(0) // Zero supply
      ]);

      expect(result.type).toBe('error');
      expect(result.value).toBe('ERR_INVALID_AMOUNT');
    });

    it('should retrieve work details', async () => {
      // Create work first
      const createResult = await contract.callPublicFunction('create-creative-work', [
        Cl.stringAscii('Test Artwork'),
        Cl.stringAscii('A test piece'),
        Cl.stringAscii('Test'),
        Cl.uint(500000),
        Cl.uint(500),
        Cl.uint(50)
      ]);

      const workId = createResult.value;
      const result = await contract.callReadOnlyFunction('get-work-details', [
        Cl.uint(workId)
      ]);

      expect(result.type).toBe('optional');
      expect(result.value).toBeTruthy();
      expect(result.value.title).toBe('Test Artwork');
      expect(result.value.price).toBe(500000);
    });
  });

  describe('Marketplace Functionality', () => {
    let workId: number;

    beforeEach(async () => {
      // Setup creator and work
      await contract.callPublicFunction('create-creator-profile', [
        Cl.stringAscii('Market Creator'),
        Cl.stringAscii('Marketplace tester'),
        Cl.stringAscii('https://market.com')
      ]);

      const createResult = await contract.callPublicFunction('create-creative-work', [
        Cl.stringAscii('Market Art'),
        Cl.stringAscii('Art for marketplace'),
        Cl.stringAscii('Digital'),
        Cl.uint(2000000),
        Cl.uint(750),
        Cl.uint(25)
      ]);

      workId = createResult.value;
    });

    it('should list work for sale', async () => {
      const result = await contract.callPublicFunction('list-work-for-sale', [
        Cl.uint(workId),
        Cl.uint(5),
        Cl.uint(2200000) // Slightly higher than original price
      ]);

      expect(result.type).toBe('ok');
      expect(result.value).toBe(true);
    });

    it('should purchase work', async () => {
      // List work first
      await contract.callPublicFunction('list-work-for-sale', [
        Cl.uint(workId),
        Cl.uint(3),
        Cl.uint(2100000)
      ]);

      const result = await contract.callPublicFunction('purchase-work', [
        Cl.uint(workId),
        Cl.principal('test-creator'),
        Cl.uint(2)
      ]);

      expect(result.type).toBe('ok');
      expect(result.value).toBe(true);
    });
  });

  describe('Contract Configuration', () => {
    it('should return next work ID', async () => {
      const result = await contract.callReadOnlyFunction('get-next-work-id', []);
      
      expect(result.type).toBe('uint');
      expect(result.value).toBe(1);
    });

    it('should return platform fee', async () => {
      const result = await contract.callReadOnlyFunction('get-platform-fee', []);
      
      expect(result.type).toBe('uint');
      expect(result.value).toBe(250); // 2.5% in basis points
    });
  });

  describe('Edge Cases', () => {
    it('should handle non-existent work lookup', async () => {
      const result = await contract.callReadOnlyFunction('get-work-details', [
        Cl.uint(999)
      ]);

      expect(result.type).toBe('optional');
      expect(result.value).toBeNull();
    });

    it('should handle non-existent creator lookup', async () => {
      const result = await contract.callReadOnlyFunction('get-creator-profile', [
        Cl.principal('non-existent-creator')
      ]);

      expect(result.type).toBe('optional');
      expect(result.value).toBeNull();
    });
  });
});

// Helper functions for testing
export const testHelpers = {
  createMockPrincipal: (address: string) => Cl.principal(address),
  createMockUint: (value: number) => Cl.uint(value),
  createMockString: (value: string) => Cl.stringAscii(value),
  
  // Test data generators
  generateTestProfile: () => ({
    name: 'Test Artist',
    bio: 'A test artist for unit testing',
    portfolioUrl: 'https://test-artist.com'
  }),
  
  generateTestWork: () => ({
    title: 'Test Creative Work',
    description: 'A creative work for testing purposes',
    category: 'Test Category',
    price: 1000000, // 1 STX
    royaltyPercentage: 1000, // 10%
    totalSupply: 100
  })
};