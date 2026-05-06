import React from 'react';
import { ScrollView, View, Text, StyleSheet, TouchableOpacity, StatusBar } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router, Stack } from 'expo-router';
import { ArrowLeft } from 'lucide-react-native';

export default function PrivacyPolicyScreen() {
  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <Stack.Screen options={{ headerShown: false }} />
      <StatusBar barStyle="light-content" />

      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <ArrowLeft size={22} color="#FFF" />
        </TouchableOpacity>
        <View>
          <Text style={styles.eyebrow}>LEGAL</Text>
          <Text style={styles.title}>Política de Privacidad</Text>
        </View>
        <View style={{ width: 40 }} />
      </View>

      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <Text style={styles.updated}>Última actualización: mayo 2026</Text>

        <Section title="1. Quiénes somos">
          Fuxia Ballerinas ("Fuxia", "nosotros") opera la aplicación móvil Fuxia Ballerinas y el sitio web fuxiaballerinas.com. Somos responsables del tratamiento de tus datos personales conforme a esta política.
        </Section>

        <Section title="2. Datos que recopilamos">
          {`• Nombre y correo electrónico — para identificarte y comunicarnos contigo.\n• Número de teléfono — para enviarte tu código de acceso (OTP) y notificaciones por WhatsApp.\n• Historial de compras — para calcular tus puntos del Programa Hilo y mostrarte tus pedidos.\n• Foto de perfil — si decides cargarla, se almacena de forma segura.\n• Token de notificaciones push — para enviarte alertas de tu pedido y puntos acumulados.\n• Dirección de envío — para completar la entrega de tus pedidos.`}
        </Section>

        <Section title="3. Cómo usamos tus datos">
          {`• Operar tu cuenta y la tarjeta de lealtad Hilo.\n• Procesar y rastrear tus pedidos.\n• Enviarte notificaciones sobre tus compras y niveles.\n• Mejorar la experiencia de la app.\n• Cumplir obligaciones legales y fiscales.`}
        </Section>

        <Section title="4. Con quién compartimos tu información">
          {`Tus datos no se venden a terceros. Solo los compartimos con:\n• Supabase — almacenamiento seguro de datos (servidores en EE.UU. bajo certificación SOC 2).\n• Stripe / Mercado Pago — procesamiento de pagos certificado PCI-DSS.\n• Twilio — envío de mensajes WhatsApp y OTP.\n• DHL / FedEx — datos de envío necesarios para la entrega.\n• WooCommerce — sincronización de pedidos del sitio web.`}
        </Section>

        <Section title="5. Seguridad">
          Usamos cifrado TLS en tránsito y Row-Level Security (RLS) en base de datos. Nunca almacenamos datos de tarjeta de crédito — son procesados directamente por Stripe con certificación PCI-DSS nivel 1.
        </Section>

        <Section title="6. Tus derechos">
          {`Tienes derecho a:\n• Acceder a tus datos personales.\n• Corregir información incorrecta.\n• Solicitar la eliminación de tu cuenta y datos.\n• Oponerte al tratamiento para fines de marketing.\n\nEscríbenos a info@fuxiaballerinas.com para ejercer cualquiera de estos derechos.`}
        </Section>

        <Section title="7. Retención de datos">
          Conservamos tus datos mientras tu cuenta esté activa o según lo requiera la ley. Si eliminas tu cuenta, borramos tus datos personales en un plazo de 30 días, excepto los registros contables que la ley fiscal exige conservar.
        </Section>

        <Section title="8. Menores de edad">
          La app está dirigida a personas mayores de 18 años. No recopilamos datos de menores de forma intencional.
        </Section>

        <Section title="9. Cambios a esta política">
          Te notificaremos por correo o notificación push si realizamos cambios significativos. El uso continuado de la app después de la notificación implica tu aceptación.
        </Section>

        <Section title="10. Contacto">
          {`Fuxia Ballerinas\ninfo@fuxiaballerinas.com\nAv. Contreras 516, San Jerónimo Lídice, CDMX`}
        </Section>

        <View style={{ height: 60 }} />
      </ScrollView>
    </SafeAreaView>
  );
}

function Section({ title, children }: { title: string; children: string }) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      <Text style={styles.body}>{children}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0D0D0D' },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
  },
  backBtn: {
    width: 40, height: 40, borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center', alignItems: 'center',
  },
  eyebrow: {
    fontSize: 10, color: '#CD7F32', fontWeight: '800',
    letterSpacing: 3, marginBottom: 2, textAlign: 'center',
  },
  title: { fontSize: 18, color: '#FFF', fontFamily: 'serif', textAlign: 'center' },
  scroll: { paddingHorizontal: 24, paddingTop: 8 },
  updated: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 11,
    marginBottom: 24,
    letterSpacing: 0.5,
  },
  section: { marginBottom: 24 },
  sectionTitle: {
    color: '#CD7F32',
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 1,
    marginBottom: 8,
  },
  body: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 13,
    lineHeight: 21,
  },
});
