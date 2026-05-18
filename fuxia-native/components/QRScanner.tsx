import React, { useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Modal } from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { X } from 'lucide-react-native';

interface QRScannerProps {
  visible: boolean;
  onScan: (data: string) => void;
  onClose: () => void;
}

export default function QRScanner({ visible, onScan, onClose }: QRScannerProps) {
  const [permission, requestPermission] = useCameraPermissions();
  const scanned = React.useRef(false);

  useEffect(() => {
    if (visible) {
      scanned.current = false;
      if (!permission?.granted) requestPermission();
    }
  }, [visible]);

  const handleBarcode = ({ data }: { data: string }) => {
    if (scanned.current) return;
    if (!data.startsWith('FX-')) return;
    scanned.current = true;
    onScan(data);
  };

  return (
    <Modal visible={visible} animationType="slide" statusBarTranslucent>
      <View style={styles.container}>
        {permission?.granted ? (
          <CameraView
            style={StyleSheet.absoluteFillObject}
            facing="back"
            onBarcodeScanned={handleBarcode}
            barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
          />
        ) : (
          <View style={styles.noPermission}>
            <Text style={styles.noPermText}>Se necesita acceso a la cámara</Text>
            <TouchableOpacity style={styles.permBtn} onPress={requestPermission}>
              <Text style={styles.permBtnText}>Dar permiso</Text>
            </TouchableOpacity>
          </View>
        )}

        {/* Guide overlay */}
        <View style={styles.overlay}>
          <View style={styles.topDim} />
          <View style={styles.middleRow}>
            <View style={styles.sideDim} />
            <View style={styles.frame}>
              <View style={[styles.corner, styles.cornerTL]} />
              <View style={[styles.corner, styles.cornerTR]} />
              <View style={[styles.corner, styles.cornerBL]} />
              <View style={[styles.corner, styles.cornerBR]} />
            </View>
            <View style={styles.sideDim} />
          </View>
          <View style={styles.bottomDim}>
            <Text style={styles.hint}>Apunta al QR de la tarjeta Fuxia</Text>
          </View>
        </View>

        <TouchableOpacity style={styles.closeBtn} onPress={onClose} activeOpacity={0.8}>
          <X size={20} color="#fff" />
        </TouchableOpacity>
      </View>
    </Modal>
  );
}

const FRAME = 240;
const DIM = 'rgba(0,0,0,0.65)';
const CORNER = 24;
const BORDER = 3;

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  noPermission: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: '#0D0D0D' },
  noPermText: { color: '#fff', fontSize: 16, marginBottom: 20 },
  permBtn: { backgroundColor: '#B8860B', paddingHorizontal: 28, paddingVertical: 14, borderRadius: 30 },
  permBtnText: { color: '#0D0D0D', fontWeight: '800', fontSize: 15 },
  overlay: { ...StyleSheet.absoluteFillObject },
  topDim: { flex: 1, backgroundColor: DIM },
  middleRow: { flexDirection: 'row', height: FRAME },
  sideDim: { flex: 1, backgroundColor: DIM },
  bottomDim: { flex: 1, backgroundColor: DIM, alignItems: 'center', paddingTop: 24 },
  frame: { width: FRAME, height: FRAME },
  hint: { color: 'rgba(255,255,255,0.75)', fontSize: 14, textAlign: 'center' },
  corner: { position: 'absolute', width: CORNER, height: CORNER, borderColor: '#B8860B' },
  cornerTL: { top: 0, left: 0, borderTopWidth: BORDER, borderLeftWidth: BORDER },
  cornerTR: { top: 0, right: 0, borderTopWidth: BORDER, borderRightWidth: BORDER },
  cornerBL: { bottom: 0, left: 0, borderBottomWidth: BORDER, borderLeftWidth: BORDER },
  cornerBR: { bottom: 0, right: 0, borderBottomWidth: BORDER, borderRightWidth: BORDER },
  closeBtn: {
    position: 'absolute', top: 56, right: 20,
    width: 44, height: 44, borderRadius: 22,
    backgroundColor: 'rgba(0,0,0,0.6)',
    alignItems: 'center', justifyContent: 'center',
  },
});
