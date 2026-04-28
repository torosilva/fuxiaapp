export type Tier = 'bronze' | 'silver' | 'gold';
export type Channel = 'web' | 'store' | 'app';
export type RewardType = 'tier_upgrade' | 'points_redemption' | 'special';

export interface Database {
  public: {
    Tables: {
      customers: {
        Row: {
          id: string;
          phone: string;
          name: string;
          email: string | null;
          country: string;
          wc_customer_id: number | null;
          avatar_url: string | null;
          created_at: string;
        };
        Insert: Omit<Database['public']['Tables']['customers']['Row'], 'id' | 'created_at'> & { id?: string; created_at?: string };
        Update: Partial<Database['public']['Tables']['customers']['Insert']>;
      };
      loyalty_cards: {
        Row: {
          id: string;
          customer_id: string;
          qr_code: string;
          total_points: number;
          pairs_count: number;
          tier: Tier;
          created_at: string;
          updated_at: string;
        };
        Insert: Omit<Database['public']['Tables']['loyalty_cards']['Row'], 'id' | 'created_at' | 'updated_at'> & { id?: string; created_at?: string; updated_at?: string };
        Update: Partial<Database['public']['Tables']['loyalty_cards']['Insert']>;
      };
      tier_config: {
        Row: {
          tier: Tier;
          min_pairs: number;
          min_points: number;
          reward_description: string | null;
          reward_sku: string | null;
        };
        Insert: Database['public']['Tables']['tier_config']['Row'];
        Update: Partial<Database['public']['Tables']['tier_config']['Row']>;
      };
      transactions: {
        Row: {
          id: string;
          loyalty_card_id: string;
          wc_order_id: number | null;
          amount: number;
          currency: string;
          points_earned: number;
          pairs_in_order: number;
          channel: Channel;
          created_at: string;
        };
        Insert: Omit<Database['public']['Tables']['transactions']['Row'], 'id' | 'created_at'> & { id?: string; created_at?: string };
        Update: Partial<Database['public']['Tables']['transactions']['Insert']>;
      };
      purchase_items: {
        Row: {
          id: string;
          transaction_id: string;
          sku: string;
          product_name: string;
          size: string | null;
          color: string | null;
          category: string | null;
          quantity: number;
          unit_price: number | null;
        };
        Insert: Omit<Database['public']['Tables']['purchase_items']['Row'], 'id'> & { id?: string };
        Update: Partial<Database['public']['Tables']['purchase_items']['Insert']>;
      };
      rewards: {
        Row: {
          id: string;
          loyalty_card_id: string;
          type: RewardType;
          threshold_points: number | null;
          product_sku: string | null;
          description: string | null;
          redeemed_at: string | null;
          created_at: string;
        };
        Insert: Omit<Database['public']['Tables']['rewards']['Row'], 'id' | 'created_at'> & { id?: string; created_at?: string };
        Update: Partial<Database['public']['Tables']['rewards']['Insert']>;
      };
      qr_scans: {
        Row: {
          id: string;
          loyalty_card_id: string;
          store_id: string | null;
          staff_id: string | null;
          channel: 'store' | 'web';
          scanned_at: string;
        };
        Insert: Omit<Database['public']['Tables']['qr_scans']['Row'], 'id' | 'scanned_at'> & { id?: string; scanned_at?: string };
        Update: Partial<Database['public']['Tables']['qr_scans']['Insert']>;
      };
    };
  };
}
