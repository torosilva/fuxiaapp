import React, { createContext, useContext, useState, useEffect, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/hooks/useAuth';

interface WishlistContextType {
  ids: Set<number>;
  toggle: (id: number) => void;
  has: (id: number) => boolean;
  loading: boolean;
}

const WishlistContext = createContext<WishlistContextType>({
  ids: new Set(),
  toggle: () => {},
  has: () => false,
  loading: false,
});

export const WishlistProvider = ({ children }: { children: React.ReactNode }) => {
  const { customer } = useAuth();
  const [ids, setIds] = useState<Set<number>>(new Set());
  const [loading, setLoading] = useState(false);

  // Cargar favoritos desde Supabase cuando el cliente esté disponible
  useEffect(() => {
    if (!customer) { setIds(new Set()); return; }
    (async () => {
      setLoading(true);
      const { data } = await supabase
        .from('wishlists')
        .select('wc_product_id')
        .eq('customer_id', customer.id);
      if (data) setIds(new Set(data.map(r => r.wc_product_id)));
      setLoading(false);
    })();
  }, [customer?.id]);

  const toggle = useCallback(async (productId: number) => {
    if (!customer) return;

    // Optimistic update
    setIds(prev => {
      const next = new Set(prev);
      next.has(productId) ? next.delete(productId) : next.add(productId);
      return next;
    });

    const isLiked = ids.has(productId);

    if (isLiked) {
      await supabase
        .from('wishlists')
        .delete()
        .eq('customer_id', customer.id)
        .eq('wc_product_id', productId);
    } else {
      await supabase
        .from('wishlists')
        .upsert({ customer_id: customer.id, wc_product_id: productId });
    }
  }, [customer, ids]);

  const has = (id: number) => ids.has(id);

  return (
    <WishlistContext.Provider value={{ ids, toggle, has, loading }}>
      {children}
    </WishlistContext.Provider>
  );
};

export const useWishlist = () => useContext(WishlistContext);
