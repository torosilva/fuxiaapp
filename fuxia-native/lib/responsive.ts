import { useWindowDimensions } from 'react-native';

export const TABLET_MIN_WIDTH = 600;
export const FORM_MAX_WIDTH = 480;

export function useResponsive() {
  const { width, height } = useWindowDimensions();
  const isTablet = width >= TABLET_MIN_WIDTH;
  return {
    width,
    height,
    isTablet,
    formMaxWidth: FORM_MAX_WIDTH,
  };
}
