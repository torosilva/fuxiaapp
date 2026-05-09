import React, { useState } from 'react';
import {
  Modal, View, Text, StyleSheet, TouchableOpacity,
  Image, ActivityIndicator, ScrollView, Dimensions,
} from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import { MotiView } from 'moti';
import { X, Camera, ImageIcon, Sparkles, RefreshCw } from 'lucide-react-native';

const { width } = Dimensions.get('window');
const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!;

const HEADERS = {
  'Content-Type': 'application/json',
  'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
};

interface TryOnModalProps {
  visible: boolean;
  onClose: () => void;
  productImage: string;
  productName: string;
}

type Step = 'pick' | 'loading' | 'result' | 'error';

async function imageToBase64(uri: string): Promise<string> {
  const res = await fetch(uri);
  const blob = await res.blob();
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve((reader.result as string).split(',')[1]);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

export function TryOnModal({ visible, onClose, productImage, productName }: TryOnModalProps) {
  const [step, setStep] = useState<Step>('pick');
  const [resultUrl, setResultUrl] = useState<string | null>(null);
  const [userPhotoUri, setUserPhotoUri] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState('');

  const reset = () => {
    setStep('pick');
    setResultUrl(null);
    setUserPhotoUri(null);
    setErrorMsg('');
  };

  const handleClose = () => { reset(); onClose(); };

  const pickAndRun = async (fromCamera: boolean) => {
    try {
      if (fromCamera) {
        const { status } = await ImagePicker.requestCameraPermissionsAsync();
        if (status !== 'granted') {
          setErrorMsg('Necesitamos permiso para usar la cámara. Actívalo en Configuración > Fuxia.');
          setStep('error');
          return;
        }
      } else {
        const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
        if (status !== 'granted') {
          setErrorMsg('Necesitamos permiso para acceder a tu galería. Actívalo en Configuración > Fuxia.');
          setStep('error');
          return;
        }
      }

      const result = fromCamera
        ? await ImagePicker.launchCameraAsync({
            mediaTypes: ImagePicker.MediaTypeOptions.Images,
            quality: 0.8,
            allowsEditing: false,
          })
        : await ImagePicker.launchImageLibraryAsync({
            mediaTypes: ImagePicker.MediaTypeOptions.Images,
            quality: 0.8,
            allowsEditing: false,
          });

      if (result.canceled || !result.assets[0]) return;

      const uri = result.assets[0].uri;
      setUserPhotoUri(uri);
      setStep('loading');

      // Convert both images to base64 data URIs
      const [humanB64, garmentB64] = await Promise.all([
        imageToBase64(uri),
        imageToBase64(productImage),
      ]);

      const human_image = `data:image/jpeg;base64,${humanB64}`;
      const garment_image = `data:image/jpeg;base64,${garmentB64}`;

      // Start try-on
      const res = await fetch(`${SUPABASE_URL}/functions/v1/virtual-tryon`, {
        method: 'POST',
        headers: HEADERS,
        body: JSON.stringify({ human_image, garment_image, category: 'shoes' }),
      });

      const data = await res.json();

      if (!res.ok) throw new Error(data.error ?? 'Error al procesar');

      // If already done
      if (data.status === 'succeeded' && data.output) {
        setResultUrl(data.output);
        setStep('result');
        return;
      }

      // Poll for result
      if (data.id) {
        await pollResult(data.id);
        return;
      }

      throw new Error('Respuesta inesperada');
    } catch (e: any) {
      setErrorMsg(e.message ?? 'Algo salió mal, intenta de nuevo');
      setStep('error');
    }
  };

  const pollResult = async (id: string) => {
    const MAX_ATTEMPTS = 20;
    for (let i = 0; i < MAX_ATTEMPTS; i++) {
      await new Promise(r => setTimeout(r, 3000));
      try {
        const res = await fetch(`${SUPABASE_URL}/functions/v1/virtual-tryon-status`, {
          method: 'POST',
          headers: HEADERS,
          body: JSON.stringify({ id }),
        });
        const data = await res.json();
        if (data.status === 'succeeded' && data.output) {
          setResultUrl(data.output);
          setStep('result');
          return;
        }
        if (data.status === 'failed') throw new Error('El modelo no pudo procesar la imagen');
      } catch (e: any) {
        setErrorMsg(e.message);
        setStep('error');
        return;
      }
    }
    setErrorMsg('Tomó demasiado tiempo. Intenta de nuevo.');
    setStep('error');
  };

  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={handleClose}>
      <View style={styles.container}>
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity onPress={handleClose} style={styles.closeBtn}>
            <X size={20} color="#FFF" />
          </TouchableOpacity>
          <View style={styles.headerCenter}>
            <Sparkles size={14} color="#CD7F32" />
            <Text style={styles.headerTitle}>Pruébatelo</Text>
          </View>
          {step !== 'pick' && (
            <TouchableOpacity onPress={reset} style={styles.closeBtn}>
              <RefreshCw size={18} color="rgba(255,255,255,0.5)" />
            </TouchableOpacity>
          )}
          {step === 'pick' && <View style={{ width: 40 }} />}
        </View>

        <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>

          {/* PICK STEP */}
          {step === 'pick' && (
            <MotiView from={{ opacity: 0, translateY: 20 }} animate={{ opacity: 1, translateY: 0 }}>
              <View style={styles.productPreview}>
                <Image source={{ uri: productImage }} style={styles.productImg} resizeMode="cover" />
                <View style={styles.productLabel}>
                  <Text style={styles.productLabelText} numberOfLines={1}>{productName}</Text>
                </View>
              </View>

              <Text style={styles.instructTitle}>¿Cómo se verán en ti?</Text>
              <Text style={styles.instructSub}>
                Toma una foto de cuerpo completo o de tus pies y la IA te muestra cómo quedan.
              </Text>

              <View style={styles.tipBox}>
                <Text style={styles.tipTitle}>💡 Para mejor resultado:</Text>
                <Text style={styles.tipText}>• Foto de pie completo o de cuerpo</Text>
                <Text style={styles.tipText}>• Buena iluminación</Text>
                <Text style={styles.tipText}>• Fondo simple o blanco</Text>
              </View>

              <TouchableOpacity style={styles.primaryBtn} onPress={() => pickAndRun(true)} activeOpacity={0.85}>
                <Camera size={18} color="#0D0D0D" />
                <Text style={styles.primaryBtnText}>Tomar foto</Text>
              </TouchableOpacity>

              <TouchableOpacity style={styles.secondaryBtn} onPress={() => pickAndRun(false)} activeOpacity={0.85}>
                <ImageIcon size={18} color="#FFF" />
                <Text style={styles.secondaryBtnText}>Subir desde galería</Text>
              </TouchableOpacity>
            </MotiView>
          )}

          {/* LOADING STEP */}
          {step === 'loading' && (
            <MotiView
              from={{ opacity: 0 }} animate={{ opacity: 1 }}
              style={styles.loadingContainer}
            >
              {userPhotoUri && (
                <Image source={{ uri: userPhotoUri }} style={styles.loadingPhoto} resizeMode="cover" />
              )}
              <View style={styles.loadingOverlay}>
                <ActivityIndicator size="large" color="#CD7F32" />
                <Text style={styles.loadingTitle}>Generando tu look ✨</Text>
                <Text style={styles.loadingSubtitle}>La IA está probando los zapatos en tu foto...</Text>
              </View>
            </MotiView>
          )}

          {/* RESULT STEP */}
          {step === 'result' && resultUrl && (
            <MotiView from={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }}>
              <Text style={styles.resultTitle}>¡Así te quedan! 👠</Text>
              <Image source={{ uri: resultUrl }} style={styles.resultImage} resizeMode="contain" />
              <Text style={styles.resultDisclaimer}>
                Resultado generado por IA — puede variar del look real.
              </Text>
              <TouchableOpacity style={styles.primaryBtn} onPress={reset} activeOpacity={0.85}>
                <RefreshCw size={18} color="#0D0D0D" />
                <Text style={styles.primaryBtnText}>Intentar con otra foto</Text>
              </TouchableOpacity>
            </MotiView>
          )}

          {/* ERROR STEP */}
          {step === 'error' && (
            <MotiView from={{ opacity: 0 }} animate={{ opacity: 1 }} style={styles.errorContainer}>
              <Text style={styles.errorEmoji}>😕</Text>
              <Text style={styles.errorTitle}>Algo salió mal</Text>
              <Text style={styles.errorMsg}>{errorMsg}</Text>
              <TouchableOpacity style={styles.primaryBtn} onPress={reset} activeOpacity={0.85}>
                <Text style={styles.primaryBtnText}>Intentar de nuevo</Text>
              </TouchableOpacity>
            </MotiView>
          )}

        </ScrollView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 20, paddingTop: 16, paddingBottom: 12,
    borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.06)',
  },
  closeBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.07)',
    justifyContent: 'center', alignItems: 'center',
  },
  headerCenter: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  headerTitle: { color: '#FFF', fontSize: 15, fontWeight: '600' },
  scroll: { padding: 24, paddingBottom: 60 },

  productPreview: {
    borderRadius: 16, overflow: 'hidden', marginBottom: 24,
    height: 220, backgroundColor: '#1A1A1A',
  },
  productImg: { width: '100%', height: '100%' },
  productLabel: {
    position: 'absolute', bottom: 0, left: 0, right: 0,
    backgroundColor: 'rgba(0,0,0,0.55)', paddingHorizontal: 16, paddingVertical: 10,
  },
  productLabelText: { color: '#FFF', fontSize: 13, fontWeight: '600' },

  instructTitle: {
    color: '#FFF', fontSize: 22, fontFamily: 'serif',
    fontWeight: '400', textAlign: 'center', marginBottom: 8,
  },
  instructSub: {
    color: 'rgba(255,255,255,0.5)', fontSize: 13, textAlign: 'center',
    lineHeight: 20, marginBottom: 24,
  },
  tipBox: {
    backgroundColor: 'rgba(205,127,50,0.08)', borderRadius: 14,
    borderWidth: 1, borderColor: 'rgba(205,127,50,0.2)',
    padding: 14, marginBottom: 28, gap: 4,
  },
  tipTitle: { color: '#CD7F32', fontSize: 12, fontWeight: '700', marginBottom: 4 },
  tipText: { color: 'rgba(255,255,255,0.55)', fontSize: 12, lineHeight: 18 },

  primaryBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 8, backgroundColor: '#CD7F32', borderRadius: 30,
    paddingVertical: 16, marginBottom: 12,
  },
  primaryBtnText: { color: '#0D0D0D', fontSize: 14, fontWeight: '800', letterSpacing: 0.5 },
  secondaryBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 8, backgroundColor: 'rgba(255,255,255,0.07)', borderRadius: 30,
    paddingVertical: 16, borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)',
  },
  secondaryBtnText: { color: '#FFF', fontSize: 14, fontWeight: '600' },

  loadingContainer: { alignItems: 'center', minHeight: 400 },
  loadingPhoto: {
    width: width - 48, height: 380, borderRadius: 16,
    backgroundColor: '#1A1A1A',
  },
  loadingOverlay: {
    position: 'absolute', bottom: 0, left: 0, right: 0,
    backgroundColor: 'rgba(13,13,13,0.85)', borderRadius: 16,
    padding: 24, alignItems: 'center', gap: 8,
  },
  loadingTitle: { color: '#FFF', fontSize: 16, fontWeight: '700', marginTop: 12 },
  loadingSubtitle: { color: 'rgba(255,255,255,0.5)', fontSize: 12, textAlign: 'center' },

  resultTitle: {
    color: '#FFF', fontSize: 22, fontFamily: 'serif',
    textAlign: 'center', marginBottom: 16,
  },
  resultImage: {
    width: width - 48, height: 480, borderRadius: 16,
    backgroundColor: '#1A1A1A', marginBottom: 12,
  },
  resultDisclaimer: {
    color: 'rgba(255,255,255,0.3)', fontSize: 11,
    textAlign: 'center', marginBottom: 24,
  },

  errorContainer: { alignItems: 'center', paddingTop: 60, gap: 12 },
  errorEmoji: { fontSize: 48 },
  errorTitle: { color: '#FFF', fontSize: 18, fontWeight: '700' },
  errorMsg: {
    color: 'rgba(255,255,255,0.5)', fontSize: 13, textAlign: 'center',
    lineHeight: 20, marginBottom: 24,
  },
});
