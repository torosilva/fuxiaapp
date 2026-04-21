import { WC_CONFIG } from '../constants/WooCommerce';

export interface WCProduct {
  id: number;
  name: string;
  slug: string;
  permalink: string;
  type: string;
  status: string;
  description: string;
  short_description: string;
  price: string;
  regular_price: string;
  sale_price: string;
  stock_status: 'instock' | 'outofstock' | 'onbackorder';
  stock_quantity: number | null;
  images: { id: number; src: string; alt: string }[];
  categories: { id: number; name: string; slug: string }[];
  variations: number[];
}

export interface WCVariation {
  id: number;
  price: string;
  regular_price: string;
  sale_price: string;
  stock_status: 'instock' | 'outofstock' | 'onbackorder';
  stock_quantity: number | null;
  attributes: { id: number; name: string; option: string }[];
}

class WooCommerceService {
  private baseUrl: string = WC_CONFIG.url;
  private consumerKey: string = WC_CONFIG.consumerKey;
  private consumerSecret: string = WC_CONFIG.consumerSecret;

  private getAuthParams(): string {
    return `consumer_key=${this.consumerKey}&consumer_secret=${this.consumerSecret}`;
  }

  async getProducts(params: string = 'per_page=20&status=publish'): Promise<WCProduct[]> {
    try {
      const response = await fetch(`${this.baseUrl}/products?${this.getAuthParams()}&${params}`);
      if (!response.ok) {
        throw new Error(`Error fetching products: ${response.statusText}`);
      }
      return await response.json();
    } catch (error) {
      console.error('WooCommerce API Error (getProducts):', error);
      return [];
    }
  }

  async getProduct(id: string): Promise<WCProduct | null> {
    try {
      const response = await fetch(`${this.baseUrl}/products/${id}?${this.getAuthParams()}`);
      if (!response.ok) {
        throw new Error(`Error fetching product ${id}: ${response.statusText}`);
      }
      return await response.json();
    } catch (error) {
      console.error(`WooCommerce API Error (getProduct ${id}):`, error);
      return null;
    }
  }

  async getProductVariations(productId: number): Promise<WCVariation[]> {
    try {
      const response = await fetch(`${this.baseUrl}/products/${productId}/variations?${this.getAuthParams()}`);
      if (!response.ok) {
        throw new Error(`Error fetching variations for product ${productId}: ${response.statusText}`);
      }
      return await response.json();
    } catch (error) {
      console.error(`WooCommerce API Error (getProductVariations ${productId}):`, error);
      return [];
    }
  }
}

export const wcService = new WooCommerceService();
