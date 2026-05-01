import React, { createContext, useContext, useState } from 'react';

interface WishlistContextType {
  ids: Set<number>;
  toggle: (id: number) => void;
  has: (id: number) => boolean;
}

const WishlistContext = createContext<WishlistContextType>({
  ids: new Set(),
  toggle: () => {},
  has: () => false,
});

export const WishlistProvider = ({ children }: { children: React.ReactNode }) => {
  const [ids, setIds] = useState<Set<number>>(new Set());

  const toggle = (id: number) => {
    setIds(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const has = (id: number) => ids.has(id);

  return (
    <WishlistContext.Provider value={{ ids, toggle, has }}>
      {children}
    </WishlistContext.Provider>
  );
};

export const useWishlist = () => useContext(WishlistContext);
