import React, { useState, useEffect } from 'react';
import { 
  Home, 
  ShoppingBag, 
  Heart, 
  User, 
  Search, 
  ChevronRight, 
  Star, 
  Package, 
  Gift, 
  CreditCard,
  Bell,
  CheckCircle2,
  MapPin,
  ArrowRight
} from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';

// --- Assets ---
const HERO_IMAGE = '/assets/hero.png';
const SANDALS_IMAGE = '/assets/sandals.png';

// --- Components ---

const BottomNav = ({ activeTab, setActiveTab }) => {
  const tabs = [
    { id: 'home', icon: Home, label: 'Inicio' },
    { id: 'shop', icon: ShoppingBag, label: 'Tienda' },
    { id: 'wishlist', icon: Heart, label: 'Wishlist' },
    { id: 'profile', icon: User, label: 'Perfil' },
  ];

  return (
    <nav style={{
      position: 'fixed',
      bottom: 0,
      width: '100%',
      maxWidth: '450px',
      height: '70px',
      backgroundColor: 'white',
      display: 'flex',
      justifyContent: 'space-around',
      alignItems: 'center',
      borderTop: '1px solid var(--border)',
      paddingBottom: 'env(safe-area-inset-bottom)',
      zIndex: 1000,
    }}>
      {tabs.map((tab) => (
        <button 
          key={tab.id}
          onClick={() => setActiveTab(tab.id)}
          style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            color: activeTab === tab.id ? 'var(--accent)' : 'var(--text-muted)',
            flex: 1,
            gap: '4px'
          }}
        >
          <tab.icon size={22} />
          <span style={{ fontSize: '10px', fontWeight: 500 }}>{tab.label}</span>
          {activeTab === tab.id && (
            <motion.div 
              layoutId="nav-pill"
              style={{
                width: '4px',
                height: '4px',
                borderRadius: '50%',
                backgroundColor: 'var(--accent)',
                marginTop: '2px'
              }}
            />
          )}
        </button>
      ))}
    </nav>
  );
};

const Header = ({ title, showSearch = true }) => (
  <header style={{
    padding: '20px var(--spacing)',
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    position: 'sticky',
    top: 0,
    backgroundColor: 'rgba(255,255,255,0.8)',
    backdropFilter: 'blur(10px)',
    zIndex: 100
  }}>
    <h2 style={{ fontSize: '24px', letterSpacing: '1px' }}>{title}</h2>
    <div style={{ display: 'flex', gap: '16px' }}>
      {showSearch && <Search size={22} />}
      <Bell size={22} />
    </div>
  </header>
);

// --- Pages ---

const HomePage = ({ onProductClick }) => (
  <motion.div 
    initial={{ opacity: 0 }} 
    animate={{ opacity: 1 }} 
    exit={{ opacity: 0 }}
    style={{ paddingBottom: '20px' }}
  >
    {/* Hero Section */}
    <div style={{ position: 'relative', width: '100%', height: '400px', overflow: 'hidden' }}>
      <img 
        src={HERO_IMAGE} 
        alt="Fuxia Ballerinas Collection" 
        style={{ width: '100%', height: '100%', objectFit: 'cover' }} 
      />
      <div style={{
        position: 'absolute',
        bottom: 0,
        left: 0,
        right: 0,
        padding: '30px var(--spacing)',
        background: 'linear-gradient(to top, rgba(0,0,0,0.6), transparent)',
        color: 'white'
      }}>
        <h1 style={{ fontSize: '36px', marginBottom: '8px' }}>Colección 2025</h1>
        <p style={{ fontSize: '14px', maxWidth: '80%', opacity: 0.9 }}>Descubre la elegancia y confort en cada paso.</p>
        <button 
          onClick={() => onProductClick('Ballerina Modelo 2025', HERO_IMAGE)}
          style={{
            marginTop: '16px',
            padding: '12px 24px',
            backgroundColor: 'var(--accent)',
            color: 'white',
            borderRadius: '25px',
            fontSize: '14px',
            fontWeight: 600
          }}>
          Ver Ahora
        </button>
      </div>
    </div>

    {/* Categories */}
    <section style={{ padding: '30px var(--spacing)' }}>
      <h3 style={{ fontSize: '20px', marginBottom: '20px' }}>Categorías</h3>
      <div style={{ display: 'flex', gap: '12px', overflowX: 'auto', paddingBottom: '10px' }}>
        {['Ballerinas', 'Sandalias', 'Botas', 'Sale'].map((cat) => (
          <div key={cat} style={{
            minWidth: '100px',
            height: '100px',
            borderRadius: 'var(--border-radius)',
            backgroundColor: 'var(--bg-soft)',
            display: 'flex',
            flexDirection: 'column',
            justifyContent: 'center',
            alignItems: 'center',
            gap: '8px',
            border: '1px solid var(--border)'
          }}>
            <span style={{ fontSize: '13px', fontWeight: 500 }}>{cat}</span>
          </div>
        ))}
      </div>
    </section>

    {/* Featured Grid */}
    <section style={{ padding: '0 var(--spacing)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
        <h3 style={{ fontSize: '20px' }}>Lo Más Vendido</h3>
        <span style={{ fontSize: '12px', color: 'var(--accent)', fontWeight: 600 }}>Ver todo</span>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
        {[1, 2].map((id) => (
          <div key={id} style={{ marginBottom: '20px' }} onClick={() => onProductClick(id === 1 ? 'Ballerina Beige Gold' : 'Sandalia Bronze', id === 1 ? HERO_IMAGE : SANDALS_IMAGE)}>
            <div style={{ 
              height: '200px', 
              borderRadius: 'var(--border-radius)', 
              backgroundColor: 'var(--bg-soft)',
              overflow: 'hidden',
              position: 'relative'
            }}>
              <img src={id === 1 ? HERO_IMAGE : SANDALS_IMAGE} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              <button style={{ position: 'absolute', top: '10px', right: '10px', backgroundColor: 'white', padding: '6px', borderRadius: '50%' }} onClick={(e) => e.stopPropagation()}>
                <Heart size={16} />
              </button>
            </div>
            <h4 style={{ marginTop: '10px', fontSize: '14px', fontWeight: 500 }}>{id === 1 ? 'Ballerina Beige Gold' : 'Sandalia Bronze'}</h4>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: '4px' }}>
              <span style={{ fontSize: '14px', fontWeight: 600 }}>$2,800 MXN</span>
              <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
                <Star size={12} fill="var(--accent)" color="var(--accent)" />
                <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>4.9</span>
              </div>
            </div>
          </div>
        ))}
      </div>
    </section>
  </motion.div>
);

const ShopPage = ({ onProductClick }) => (
  <motion.div 
    initial={{ opacity: 0 }} 
    animate={{ opacity: 1 }}
    style={{ padding: '0 var(--spacing) 100px' }}
  >
    <Header title="Fuxia Shop" />
    <div style={{ display: 'flex', gap: '8px', marginBottom: '20px', overflowX: 'auto', whiteSpace: 'nowrap' }}>
       {['Todo', 'Ballerinas', 'Sandalias', 'Planas', 'Botas'].map(f => (
         <button key={f} style={{ 
           padding: '8px 16px', 
           borderRadius: '20px', 
           border: '1px solid var(--border)',
           fontSize: '13px',
           backgroundColor: f === 'Todo' ? 'var(--primary)' : 'white',
           color: f === 'Todo' ? 'white' : 'var(--primary)'
         }}>
           {f}
         </button>
       ))}
    </div>
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
      {[1, 2, 3, 4].map(i => (
        <div key={i} className="fade-in" style={{ animationDelay: `${i * 0.1}s` }} onClick={() => onProductClick('Modelo Fuxia ' + i, i % 2 === 0 ? SANDALS_IMAGE : HERO_IMAGE)}>
          <div style={{ height: '220px', backgroundColor: 'var(--bg-soft)', borderRadius: '12px', overflow: 'hidden' }}>
            <img src={i % 2 === 0 ? SANDALS_IMAGE : HERO_IMAGE} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          </div>
          <div style={{ padding: '8px 0' }}>
            <p style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Ballerinas</p>
            <p style={{ fontSize: '14px', fontWeight: 500 }}>Modelo Clásico Fuxia</p>
            <p style={{ fontSize: '14px', fontWeight: 600, marginTop: '4px' }}>$3,200 MXN</p>
          </div>
        </div>
      ))}
    </div>
  </motion.div>
);

const ProfilePage = () => {
  const [showPointsDetail, setShowPointsDetail] = useState(false);

  return (
    <motion.div 
      initial={{ opacity: 0 }} 
      animate={{ opacity: 1 }}
      style={{ padding: '0 var(--spacing) 100px' }}
    >
      <header style={{ padding: '40px 0', textAlign: 'center' }}>
        <div style={{ width: '80px', height: '80px', borderRadius: '50%', backgroundColor: 'var(--bg-soft)', margin: '0 auto 16px', display: 'flex', alignItems: 'center', justifyContent: 'center', border: '2px solid var(--accent)' }}>
          <User size={40} color="var(--accent)" />
        </div>
        <h2 style={{ fontSize: '24px' }}>Maria Garcia</h2>
        <p style={{ fontSize: '14px', color: 'var(--text-muted)' }}>maria.garcia@example.com</p>
      </header>

      {/* Loyalty Card */}
      <motion.div 
        whileTap={{ scale: 0.98 }}
        style={{
          background: 'linear-gradient(135deg, #1A1A1A, #333)',
          borderRadius: '20px',
          padding: '24px',
          color: 'white',
          marginBottom: '30px',
          position: 'relative',
          overflow: 'hidden'
        }}
      >
        <div style={{ zIndex: 1, position: 'relative' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div>
              <p style={{ fontSize: '12px', opacity: 0.7, textTransform: 'uppercase', letterSpacing: '1px' }}>Fuxia Loyalty</p>
              <h3 style={{ fontSize: '32px', margin: '4px 0' }}>1,250 <span style={{ fontSize: '14px', opacity: 0.8 }}>pts</span></h3>
            </div>
            <div style={{ backgroundColor: 'var(--accent)', padding: '4px 12px', borderRadius: '12px', fontSize: '12px', fontWeight: 600 }}>Nivel Gold</div>
          </div>
          
          <div style={{ marginTop: '20px' }}>
            <div style={{ width: '100%', height: '6px', backgroundColor: 'rgba(255,255,255,0.1)', borderRadius: '3px', position: 'relative' }}>
              <div style={{ width: '75%', height: '100%', backgroundColor: 'var(--accent)', borderRadius: '3px' }} />
            </div>
            <p style={{ fontSize: '11px', marginTop: '8px', opacity: 0.8 }}>Faltan 250 pts para el nivel Platinum</p>
          </div>
        </div>
        {/* Luxury decoration */}
        <div style={{ 
          position: 'absolute', 
          right: '-20px', 
          bottom: '-20px', 
          width: '120px', 
          height: '120px', 
          borderRadius: '50%', 
          border: '1px solid rgba(197, 160, 89, 0.2)' 
        }} />
      </motion.div>

      {/* Actions */}
      <section style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px', marginBottom: '30px' }}>
        {[
          { icon: Package, label: 'Mis Compras' },
          { icon: MapPin, label: 'Seguimiento' },
          { icon: Gift, label: 'Regalar' },
          { icon: CreditCard, label: 'Pagos' },
        ].map((item, idx) => (
          <button key={idx} style={{
            padding: '20px',
            backgroundColor: 'white',
            border: '1px solid var(--border)',
            borderRadius: '16px',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            gap: '10px'
          }}>
            <item.icon size={24} color="var(--primary)" />
            <span style={{ fontSize: '13px', fontWeight: 500 }}>{item.label}</span>
          </button>
        ))}
      </section>

      {/* Order Status */}
      <section>
        <h3 style={{ fontSize: '18px', marginBottom: '16px' }}>Último Pedido</h3>
        <div style={{ 
          padding: '16px', 
          backgroundColor: 'var(--bg-soft)', 
          borderRadius: '16px',
          display: 'flex',
          gap: '16px'
        }}>
          <div style={{ width: '60px', height: '60px', borderRadius: '12px', backgroundColor: 'white', overflow: 'hidden' }}>
            <img src={SANDALS_IMAGE} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <p style={{ fontSize: '14px', fontWeight: 600 }}>En Camino</p>
              <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>#FX-4921</span>
            </div>
            <p style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '4px' }}>Llega mañana, 14:00 - 18:00</p>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '12px' }}>
               <CheckCircle2 size={14} color="#4CAF50" />
               <div style={{ flex: 1, height: '2px', backgroundColor: '#ddd', position: 'relative' }}>
                  <div style={{ width: '60%', height: '100%', backgroundColor: '#4CAF50' }} />
               </div>
            </div>
          </div>
        </div>
      </section>
    </motion.div>
  );
};

const WishlistPage = () => (
  <motion.div 
    initial={{ opacity: 0 }} 
    animate={{ opacity: 1 }}
    style={{ padding: '0 var(--spacing) 100px' }}
  >
    <Header title="Wishlist" />
    <div style={{ textAlign: 'center', marginTop: '60px' }}>
      <Heart size={60} color="#eee" />
      <h3 style={{ marginTop: '20px' }}>Tu lista está vacía</h3>
      <p style={{ color: 'var(--text-muted)', fontSize: '14px', marginTop: '10px' }}>Guarda tus modelos favoritos para verlos después.</p>
      <button style={{
          marginTop: '24px',
          padding: '12px 30px',
          backgroundColor: 'var(--primary)',
          color: 'white',
          borderRadius: '25px',
          fontWeight: 600
        }}>
          Ir a la Tienda
      </button>
    </div>
  </motion.div>
);

const ProductDetail = ({ product, onClose }) => {
  const [selectedSize, setSelectedSize] = useState(null);
  const [isGift, setIsGift] = useState(false);

  return (
    <motion.div 
      initial={{ y: '100%' }}
      animate={{ y: 0 }}
      exit={{ y: '100%' }}
      transition={{ type: 'spring', damping: 25, stiffness: 200 }}
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        backgroundColor: 'white',
        zIndex: 2000,
        overflowY: 'auto',
        maxWidth: '450px',
        margin: '0 auto'
      }}
    >
      {/* Product Image Spacer */}
      <div style={{ position: 'relative', height: '450px' }}>
        <img src={product.image} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        <button 
          onClick={onClose}
          style={{ 
            position: 'absolute', 
            top: '20px', 
            left: '20px', 
            backgroundColor: 'rgba(255,255,255,0.8)', 
            padding: '10px', 
            borderRadius: '50%' 
          }}
        >
          <ArrowRight style={{ transform: 'rotate(180deg)' }} size={20} />
        </button>
      </div>

      <div style={{ padding: '30px var(--spacing)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <div>
            <h2 style={{ fontSize: '28px' }}>{product.name}</h2>
            <p style={{ color: 'var(--text-muted)', fontSize: '16px', marginTop: '4px' }}>Ballerinas de Cuero</p>
          </div>
          <p style={{ fontSize: '22px', fontWeight: 600 }}>$2,800</p>
        </div>

        {/* Size Selector */}
        <div style={{ marginTop: '30px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '12px' }}>
            <h3 style={{ fontSize: '16px' }}>Selecciona tu talla</h3>
            <span style={{ fontSize: '12px', color: 'var(--accent)', fontWeight: 600 }}>Guía de tallas</span>
          </div>
          <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
            {['35', '36', '37', '38', '39', '40'].map(size => (
              <button 
                key={size}
                onClick={() => setSelectedSize(size)}
                style={{
                  width: '50px',
                  height: '50px',
                  borderRadius: '12px',
                  border: `1px solid ${selectedSize === size ? 'var(--primary)' : 'var(--border)'}`,
                  backgroundColor: selectedSize === size ? 'var(--primary)' : 'white',
                  color: selectedSize === size ? 'white' : 'var(--primary)',
                  fontWeight: 600,
                  fontSize: '14px'
                }}
              >
                {size}
              </button>
            ))}
          </div>
        </div>

        {/* Loyalty Reward Preview */}
        <div style={{ 
          marginTop: '30px', 
          backgroundColor: 'var(--bg-soft)', 
          padding: '16px', 
          borderRadius: '16px',
          display: 'flex',
          alignItems: 'center',
          gap: '12px',
          border: '1px dashed var(--accent)'
        }}>
          <Star size={20} color="var(--accent)" fill="var(--accent)" />
          <p style={{ fontSize: '13px', color: 'var(--primary)' }}>
            Compra este modelo y gana <span style={{ fontWeight: 700 }}>280 puntos Fuxia</span>
          </p>
        </div>

        {/* Gift Mode Toggle */}
        <div style={{ 
          marginTop: '30px', 
          padding: '16px', 
          border: '1px solid var(--border)', 
          borderRadius: '16px',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center'
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <Gift size={20} color="var(--accent)" />
            <div>
              <p style={{ fontSize: '14px', fontWeight: 600 }}>¿Es un regalo?</p>
              <p style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Ocultamos el precio en el ticket</p>
            </div>
          </div>
          <button 
            onClick={() => setIsGift(!isGift)}
            style={{
              width: '50px',
              height: '26px',
              borderRadius: '13px',
              backgroundColor: isGift ? 'var(--accent)' : '#eee',
              position: 'relative',
              transition: 'background-color 0.3s'
            }}
          >
            <motion.div 
              animate={{ x: isGift ? 24 : 2 }}
              style={{
                width: '22px',
                height: '22px',
                borderRadius: '50%',
                backgroundColor: 'white',
                position: 'absolute',
                top: '2px'
              }}
            />
          </button>
        </div>

        {isGift && (
          <motion.div 
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            style={{ marginTop: '16px' }}
          >
            <textarea 
              placeholder="Escribe una nota personalizada..."
              style={{
                width: '100%',
                height: '100px',
                border: '1px solid var(--border)',
                borderRadius: '12px',
                padding: '12px',
                fontSize: '14px',
                fontFamily: 'inherit',
                resize: 'none'
              }}
            />
          </motion.div>
        )}

        <button style={{
          width: '100%',
          marginTop: '40px',
          padding: '18px',
          backgroundColor: 'var(--primary)',
          color: 'white',
          borderRadius: '30px',
          fontWeight: 600,
          fontSize: '16px'
        }}>
          Añadir al Carrito
        </button>
      </div>
    </motion.div>
  );
};

export default function App() {
  const [activeTab, setActiveTab] = useState('home');
  const [selectedProduct, setSelectedProduct] = useState(null);

  // Helper to open product
  const openProduct = (name, image) => setSelectedProduct({ name, image });

  return (
    <div className="max-w-mobile">
      <AnimatePresence mode="wait">
        {activeTab === 'home' && <HomePage key="home" onProductClick={openProduct} />}
        {activeTab === 'shop' && <ShopPage key="shop" onProductClick={openProduct} />}
        {activeTab === 'wishlist' && <WishlistPage key="wishlist" />}
        {activeTab === 'profile' && <ProfilePage key="profile" />}
      </AnimatePresence>

      <AnimatePresence>
        {selectedProduct && (
          <ProductDetail 
            product={selectedProduct} 
            onClose={() => setSelectedProduct(null)} 
          />
        )}
      </AnimatePresence>

      <BottomNav activeTab={activeTab} setActiveTab={setActiveTab} />
    </div>
  );
}
